/*
 * StreamEngine.swift
 * UnicornEEG
 *
 * Manages the background acquisition thread. Reads packets from the Unicorn
 * device, parses them, feeds samples to registered output sinks, the
 * ring buffer for visualization, and the band power processor for FFT.
 */

import Foundation

class StreamEngine: ObservableObject {
    let device = UnicornDevice()
    let ringBuffer = RingBuffer(capacity: 7500) // 30 seconds at 250 Hz

    // Band power processing
    let bandPowerProcessor = BandPowerProcessor()
    let bandPowerBuffer = RingBuffer(capacity: 120, channelCount: FrequencyBand.count) // 60 seconds at ~2 Hz
    let bandPowerLSL = BandPowerLSLOutput()
    @Published var bandPowerLSLEnabled = false

    // Signal quality
    let signalQualityProcessor = SignalQualityProcessor()
    @Published var signalQuality: [ChannelQualityInfo] = []

    @Published var isConnected = false
    @Published var isStreaming = false
    @Published var isResettingBluetooth = false
    @Published var bluetoothStatusMessage: String?
    @Published var batteryLevel: Float = 0
    @Published var sampleCount: UInt64 = 0
    @Published var errorMessage: String?

    private var outputs: [OutputSink] = []
    private var acquisitionThread: Thread?

    // Thread-safe flag for stopping the acquisition loop
    private let runLock = NSLock()
    private var _shouldRun = false
    private var shouldRun: Bool {
        get { runLock.withLock { _shouldRun } }
        set { runLock.withLock { _shouldRun = newValue } }
    }

    init() {
        // When band powers are computed, write averages to the band buffer
        // and push all data to LSL
        bandPowerProcessor.onBandPowerComputed = { [weak self] result in
            guard let self = self else { return }

            // Write average band powers to the visualization ring buffer
            // Create a fake UnicornSample-like write — we use a dedicated write method
            self.bandPowerBuffer.writeRaw(result.average)

            // Push to LSL if enabled
            if self.bandPowerLSLEnabled {
                self.bandPowerLSL.pushResult(result)
            }
        }
    }

    // MARK: - Output Management

    func addOutput(_ output: OutputSink) {
        outputs.append(output)
    }

    func removeAllOutputs() {
        for output in outputs {
            output.stop()
        }
        outputs.removeAll()
    }

    // MARK: - Bluetooth Reset + Stream

    /// Reset the Bluetooth connection (unpair/re-pair if needed), then start streaming.
    func connectAndStream() {
        guard !isStreaming && !isResettingBluetooth else { return }

        DispatchQueue.main.async {
            self.isResettingBluetooth = true
            self.bluetoothStatusMessage = "Resetting Bluetooth connection..."
            self.errorMessage = nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let addr = BluetoothManager.unicornAddress() else {
                DispatchQueue.main.async {
                    self.isResettingBluetooth = false
                    self.bluetoothStatusMessage = nil
                    self.errorMessage = "No Unicorn device found in Bluetooth settings. Pair it once first."
                }
                return
            }

            print("[BT] Found Unicorn at \(addr), starting unpair/re-pair cycle")

            DispatchQueue.main.async {
                self.bluetoothStatusMessage = "Unpairing and re-pairing Bluetooth..."
            }

            let success = BluetoothManager.unpairAndRepair()

            guard success else {
                DispatchQueue.main.async {
                    self.isResettingBluetooth = false
                    self.bluetoothStatusMessage = nil
                    self.errorMessage = "Bluetooth reset failed. Is the Unicorn powered on?"
                }
                return
            }

            guard let portName = BluetoothManager.findUnicornPortName() else {
                DispatchQueue.main.async {
                    self.isResettingBluetooth = false
                    self.bluetoothStatusMessage = nil
                    self.errorMessage = "Bluetooth connected but serial port did not appear."
                }
                return
            }

            DispatchQueue.main.async {
                self.isResettingBluetooth = false
                self.bluetoothStatusMessage = nil
                self.startStreaming(portName: portName)
            }
        }
    }

    // MARK: - Streaming

    func startStreaming(portName: String) {
        guard !isStreaming else { return }

        if !isConnected {
            do {
                try device.connect(portName: portName)
                DispatchQueue.main.async {
                    self.isConnected = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }
        }

        do {
            try device.startAcquisition()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            return
        }

        for output in outputs {
            do {
                try output.start()
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to start \(output.name): \(error.localizedDescription)"
                }
            }
        }

        // Start band power LSL if enabled
        if bandPowerLSLEnabled {
            bandPowerLSL.start(
                bandConfigs: bandPowerProcessor.bandConfigs,
                ratioConfigs: bandPowerProcessor.ratioConfigs
            )
        }

        shouldRun = true
        device.shouldStop = false
        ringBuffer.clear()
        bandPowerBuffer.clear()
        bandPowerProcessor.reset()
        signalQualityProcessor.reset()

        DispatchQueue.main.async {
            self.isStreaming = true
            self.sampleCount = 0
            self.errorMessage = nil
        }

        acquisitionThread = Thread { [weak self] in
            self?.acquisitionLoop()
        }
        acquisitionThread?.name = "UnicornAcquisition"
        acquisitionThread?.qualityOfService = .userInteractive
        acquisitionThread?.start()
    }

    func stopStreaming() {
        shouldRun = false
        device.shouldStop = true

        let deadline = Date().addingTimeInterval(2.0)
        while acquisitionThread?.isExecuting == true && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        acquisitionThread = nil

        device.stopAcquisition()

        for output in outputs {
            output.stop()
        }
        bandPowerLSL.stop()

        DispatchQueue.main.async {
            self.isStreaming = false
        }
    }

    func shutdown() {
        if isStreaming {
            stopStreaming()
        }
        device.disconnect()
        DispatchQueue.main.async {
            self.isConnected = false
            self.batteryLevel = 0
            self.sampleCount = 0
        }
    }

    // MARK: - Acquisition Loop

    private func acquisitionLoop() {
        var localCount: UInt64 = 0

        while shouldRun {
            guard let sample = device.readPacket() else {
                if shouldRun {
                    DispatchQueue.main.async {
                        self.errorMessage = "Cannot read packet — connection lost?"
                        self.isStreaming = false
                    }
                    device.stopAcquisition()
                    for output in self.outputs {
                        output.stop()
                    }
                    bandPowerLSL.stop()
                }
                return
            }

            localCount += 1
            ringBuffer.write(sample)
            bandPowerProcessor.processSample(sample)
            _ = signalQualityProcessor.processSample(sample)

            for output in outputs {
                output.processSample(sample)
            }

            if localCount % 62 == 0 {
                let bat = sample.battery
                let cnt = localCount
                let qualities = signalQualityProcessor.channelQualities
                DispatchQueue.main.async {
                    self.batteryLevel = bat
                    self.sampleCount = cnt
                    self.signalQuality = qualities
                }
            }
        }
    }
}
