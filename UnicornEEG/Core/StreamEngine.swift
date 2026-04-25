/*
 * StreamEngine.swift
 * UnicornEEG
 *
 * Manages the background acquisition thread. Reads packets from the Unicorn
 * device, parses them, feeds samples to registered output sinks and the
 * ring buffer for visualization.
 */

import Foundation

class StreamEngine: ObservableObject {
    let device = UnicornDevice()
    let ringBuffer = RingBuffer(capacity: 1250) // 5 seconds at 250 Hz

    @Published var isConnected = false
    @Published var isStreaming = false
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

    // MARK: - Connection

    func connect(portName: String) {
        guard !isConnected else { return }

        do {
            try device.connect(portName: portName)
            DispatchQueue.main.async {
                self.isConnected = true
                self.errorMessage = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() {
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

    // MARK: - Streaming

    func startStreaming() {
        guard isConnected, !isStreaming else { return }

        do {
            try device.startAcquisition()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
            }
            return
        }

        // Start output sinks
        for output in outputs {
            do {
                try output.start()
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to start \(output.name): \(error.localizedDescription)"
                }
            }
        }

        shouldRun = true
        ringBuffer.clear()

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

        // Wait briefly for acquisition thread to exit
        while acquisitionThread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.01)
        }
        acquisitionThread = nil

        device.stopAcquisition()

        for output in outputs {
            output.stop()
        }

        DispatchQueue.main.async {
            self.isStreaming = false
        }
    }

    // MARK: - Acquisition Loop

    private func acquisitionLoop() {
        var localCount: UInt64 = 0

        while shouldRun {
            guard let sample = device.readPacket() else {
                shouldRun = false
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot read packet — connection lost?"
                    self.isStreaming = false
                    self.device.stopAcquisition()
                    for output in self.outputs {
                        output.stop()
                    }
                }
                return
            }

            localCount += 1
            ringBuffer.write(sample)

            for output in outputs {
                output.processSample(sample)
            }

            // Update UI at 4 Hz (every 62 samples) to avoid flooding the main thread
            if localCount % 62 == 0 {
                let bat = sample.battery
                let cnt = localCount
                DispatchQueue.main.async {
                    self.batteryLevel = bat
                    self.sampleCount = cnt
                }
            }
        }
    }
}
