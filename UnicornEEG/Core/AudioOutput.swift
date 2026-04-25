/*
 * AudioOutput.swift
 * UnicornEEG
 *
 * Streams EEG data to an audio device via PortAudio with resampling.
 * Replaces the functionality of unicorn2audio.
 *
 * Architecture note: following the original C design, resampling happens
 * only in the PortAudio callback (single-threaded). The acquisition thread
 * only writes to the input buffer; the callback reads from the input buffer,
 * resamples, and fills the output buffer. A lock protects the shared input buffer.
 */

import Foundation

struct AudioOutputConfig {
    var outputDeviceIndex: Int = -1  // -1 = default
    var sampleRate: Float = 44100.0
    var bufferSize: Float = 2.0      // seconds
    var blockSize: Float = 0.01      // seconds
    var hpFilterTimeConstant: Float = 10.0  // seconds
    var outputLimit: Float = 1.0
    var autoScale: Bool = true
    var channelCount: Int = 8
}

struct AudioDeviceInfo {
    let index: Int
    let name: String
    let maxOutputChannels: Int
    let isDefault: Bool
}

// Shared state accessible from the C callback.
// The lock protects inputData/inputFrames which are written by the acquisition
// thread and read by the audio callback. Other fields are only accessed from
// the callback after streaming starts.
private class AudioOutputState {
    let lock = NSLock()

    var outputData: UnsafeMutablePointer<Float>?
    var outputFrames: Int = 0
    var outputBufsize: Int = 0
    var channelCount: Int = 8

    var inputData: UnsafeMutablePointer<Float>?
    var inputFrames: Int = 0
    var inputBufsize: Int = 0

    var resampleState: OpaquePointer?
    var resampleRatio: Float = 1.0
    var outputRate: Float = 44100
    var inputRate: Float = 250

    var enableResample: Bool = false
    var enableUpdateRatio: Bool = false
    var enableUpdateLimit: Bool = false
    var outputLimit: Float = 1.0
    var outputBlocksize: Int = 441
}

// Global PortAudio reference count to avoid init/terminate conflicts
private var paRefCount = 0
private let paRefLock = NSLock()

private func paRetain() {
    paRefLock.lock()
    if paRefCount == 0 {
        Pa_Initialize()
    }
    paRefCount += 1
    paRefLock.unlock()
}

private func paRelease() {
    paRefLock.lock()
    paRefCount -= 1
    if paRefCount == 0 {
        Pa_Terminate()
    }
    paRefLock.unlock()
}

class AudioOutput: OutputSink {
    let name = "Audio"
    var config: AudioOutputConfig

    private var stream: UnsafeMutableRawPointer?
    private var state = AudioOutputState()
    private var eegFilt = [Float](repeating: 0, count: 8)
    private var hpFilter: Float = 0
    private var samplesReceived: UInt64 = 0
    private var flushed = false

    init(config: AudioOutputConfig = AudioOutputConfig()) {
        self.config = config
    }

    static func listDevices() -> [AudioDeviceInfo] {
        paRetain()
        defer { paRelease() }

        let numDevices = Int(Pa_GetDeviceCount())
        let defaultDevice = Int(Pa_GetDefaultOutputDevice())
        var devices: [AudioDeviceInfo] = []

        for i in 0..<numDevices {
            guard let info = Pa_GetDeviceInfo(Int32(i)) else { continue }
            let maxOut = Int(info.pointee.maxOutputChannels)
            if maxOut > 0 {
                let name = String(cString: info.pointee.name)
                devices.append(AudioDeviceInfo(index: i, name: name,
                                               maxOutputChannels: maxOut,
                                               isDefault: i == defaultDevice))
            }
        }
        return devices
    }

    func start() throws {
        hpFilter = 1.0 - pow(0.5, 1.0 / (Float(PacketParser.sampleRate) * config.hpFilterTimeConstant))
        state.outputLimit = config.outputLimit
        state.enableUpdateLimit = config.autoScale
        state.channelCount = config.channelCount
        state.inputRate = Float(PacketParser.sampleRate)
        state.outputRate = config.sampleRate
        state.resampleRatio = config.sampleRate / Float(PacketParser.sampleRate)

        state.inputBufsize = Int(config.bufferSize * state.inputRate)
        state.outputBufsize = Int(config.bufferSize * config.sampleRate)
        state.outputBlocksize = Int(config.blockSize * config.sampleRate)

        // Allocate buffers
        state.inputData = .allocate(capacity: state.inputBufsize * config.channelCount)
        state.inputData?.initialize(repeating: 0, count: state.inputBufsize * config.channelCount)
        state.inputFrames = 0

        state.outputData = .allocate(capacity: state.outputBufsize * config.channelCount)
        state.outputData?.initialize(repeating: 0, count: state.outputBufsize * config.channelCount)
        state.outputFrames = 0

        // Set up libsamplerate
        var srcErr: Int32 = 0
        state.resampleState = src_new(Int32(SRC_SINC_MEDIUM_QUALITY), Int32(config.channelCount), &srcErr)
        guard state.resampleState != nil else {
            throw NSError(domain: "AudioOutput", code: Int(srcErr),
                          userInfo: [NSLocalizedDescriptionKey: "Cannot set up resampler: \(String(cString: src_strerror(srcErr)))"])
        }

        // Initialize PortAudio
        paRetain()

        let deviceIndex = config.outputDeviceIndex < 0 ? Pa_GetDefaultOutputDevice() : Int32(config.outputDeviceIndex)

        guard let devInfo = Pa_GetDeviceInfo(deviceIndex) else {
            paRelease()
            throw NSError(domain: "AudioOutput", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio output device available"])
        }

        var outputParams = PaStreamParameters()
        outputParams.device = deviceIndex
        outputParams.channelCount = Int32(config.channelCount)
        outputParams.sampleFormat = paFloat32
        outputParams.suggestedLatency = devInfo.pointee.defaultLowOutputLatency
        outputParams.hostApiSpecificStreamInfo = nil

        let statePtr = Unmanaged.passUnretained(state).toOpaque()

        let paErr = Pa_OpenStream(
            &stream,
            nil,
            &outputParams,
            Double(config.sampleRate),
            UInt(state.outputBlocksize),
            UInt(paNoFlag),
            audioCallback,
            statePtr
        )
        guard paErr == paNoError.rawValue else {
            paRelease()
            throw NSError(domain: "AudioOutput", code: Int(paErr),
                          userInfo: [NSLocalizedDescriptionKey: "Cannot open audio stream: \(String(cString: Pa_GetErrorText(paErr)))"])
        }

        samplesReceived = 0
        flushed = false
        eegFilt = [Float](repeating: 0, count: config.channelCount)
    }

    func processSample(_ sample: UnicornSample) {
        let cc = config.channelCount
        var eegdata = Array(sample.eeg.prefix(cc))

        samplesReceived += 1

        // Flush initial samples (first 5 seconds tend to have weird values)
        if !flushed {
            if samplesReceived < UInt64(5 * PacketParser.sampleRate) {
                return
            }
            flushed = true
            eegFilt = eegdata
            samplesReceived = 0
            state.enableResample = false
            state.enableUpdateRatio = false
        }

        // High-pass filter: subtract exponentially smoothed signal
        for i in 0..<cc {
            eegFilt[i] = (1.0 - hpFilter) * eegFilt[i] + hpFilter * eegdata[i]
            eegdata[i] -= eegFilt[i]
        }

        // Scale and add to input buffer (lock-protected, shared with callback)
        state.lock.lock()
        for i in 0..<cc {
            if state.enableUpdateLimit {
                state.outputLimit = max(state.outputLimit, abs(eegdata[i]))
            }
            let idx = state.inputFrames * cc + i
            state.inputData?[idx] = eegdata[i] / state.outputLimit
        }
        state.inputFrames += 1
        state.lock.unlock()

        // Once input buffer is half full, start audio playback
        if !state.enableResample && state.inputFrames >= state.inputBufsize / 2 {
            src_set_ratio(state.resampleState, Double(state.resampleRatio))

            if let s = stream {
                Pa_StartStream(s)
            }
            state.enableResample = true
            state.enableUpdateRatio = true
        }
    }

    func stop() {
        state.enableResample = false
        state.enableUpdateRatio = false
        state.enableUpdateLimit = false

        if let s = stream {
            Pa_StopStream(s)
            Pa_CloseStream(s)
            stream = nil
        }
        paRelease()

        if let resampleState = state.resampleState {
            src_delete(resampleState)
            state.resampleState = nil
        }

        state.inputData?.deallocate()
        state.inputData = nil
        state.outputData?.deallocate()
        state.outputData = nil
    }
}

// MARK: - PortAudio Callback (C-compatible)

private func audioCallback(
    _ input: UnsafeRawPointer?,
    _ output: UnsafeMutableRawPointer?,
    _ frameCount: UInt,
    _ timeInfo: UnsafePointer<PaStreamCallbackTimeInfo>?,
    _ statusFlags: UInt,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let userData = userData, let output = output else { return Int32(paAbort.rawValue) }

    let state = Unmanaged<AudioOutputState>.fromOpaque(userData).takeUnretainedValue()
    let data = output.assumingMemoryBound(to: Float.self)
    let cc = state.channelCount
    let frames = Int(frameCount)
    let available = min(frames, state.outputFrames)

    // Copy available data from output buffer
    if available > 0, let outputData = state.outputData {
        memcpy(data, outputData, available * cc * MemoryLayout<Float>.size)

        // Track output limit for auto-scaling
        if state.enableUpdateLimit {
            for i in 0..<(available * cc) {
                state.outputLimit = max(state.outputLimit, abs(data[i]))
            }
        }

        // Shift remaining output data (overlapping, use memmove)
        let remaining = state.outputFrames - available
        if remaining > 0 {
            memmove(outputData, outputData + available * cc, remaining * cc * MemoryLayout<Float>.size)
        }
        state.outputFrames = remaining
    }

    // Zero-fill any remaining frames
    if available < frames {
        memset(data + available * cc, 0, (frames - available) * cc * MemoryLayout<Float>.size)
    }

    // Resample input data into output buffer (lock-protected access to input buffer)
    if state.enableResample {
        state.lock.lock()
        if state.inputFrames > 0, state.outputFrames < state.outputBufsize,
           let resampleState = state.resampleState, let inputData = state.inputData, let outputData = state.outputData {
            var srcData = SRC_DATA()
            srcData.src_ratio = Double(state.resampleRatio)
            srcData.end_of_input = 0
            srcData.data_in = UnsafePointer(inputData)
            srcData.input_frames = Int(state.inputFrames)
            srcData.data_out = outputData + state.outputFrames * cc
            srcData.output_frames = Int(state.outputBufsize - state.outputFrames)

            if src_process(resampleState, &srcData) == 0 {
                state.outputFrames += Int(srcData.output_frames_gen)

                // Shift remaining input data (overlapping, use memmove)
                let remaining = state.inputFrames - Int(srcData.input_frames_used)
                if remaining > 0 {
                    let src = inputData + Int(srcData.input_frames_used) * cc
                    memmove(inputData, src, remaining * cc * MemoryLayout<Float>.size)
                }
                state.inputFrames = remaining
            }
        }
        state.lock.unlock()
    }

    // Update resample ratio
    if state.enableUpdateRatio {
        let nominal = state.outputRate / state.inputRate
        var estimate = nominal + (0.5 * Float(state.outputBufsize) - Float(state.outputFrames)) / Float(state.outputBlocksize)
        estimate = min(estimate, 1.2 * nominal)
        estimate = max(estimate, 0.8 * nominal)

        let blockSize: Float = 0.01
        let verylow = 0.40 * Float(state.outputBufsize)
        let low = 0.48 * Float(state.outputBufsize)
        let high = 0.52 * Float(state.outputBufsize)
        let veryhigh = 0.60 * Float(state.outputBufsize)
        let of = Float(state.outputFrames)

        if of < verylow {
            state.resampleRatio = (1.0 - 10.0 * blockSize) * state.resampleRatio + (10.0 * blockSize) * estimate
        } else if of < low {
            state.resampleRatio = (1.0 - 1.0 * blockSize) * state.resampleRatio + (1.0 * blockSize) * estimate
        } else if of > veryhigh {
            state.resampleRatio = (1.0 - 10.0 * blockSize) * state.resampleRatio + (10.0 * blockSize) * estimate
        } else if of > high {
            state.resampleRatio = (1.0 - 1.0 * blockSize) * state.resampleRatio + (1.0 * blockSize) * estimate
        } else {
            state.resampleRatio = (1.0 - 10.0 * blockSize) * state.resampleRatio + (10.0 * blockSize) * nominal
        }
    }

    return Int32(paContinue.rawValue)
}
