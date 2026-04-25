/*
 * TextFileOutput.swift
 * UnicornEEG
 *
 * Writes EEG data to a tab-separated text file.
 * Replaces the functionality of unicorn2txt.
 */

import Foundation

class TextFileOutput: OutputSink {
    let name = "Text File"
    var filePath: String

    private var fileHandle: FileHandle?

    init(filePath: String) {
        self.filePath = filePath
    }

    func start() throws {
        FileManager.default.createFile(atPath: filePath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: filePath)
        guard fileHandle != nil else {
            throw NSError(domain: "TextFileOutput", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot open file: \(filePath)"])
        }

        let header = "eeg1\teeg2\teeg3\teeg4\teeg5\teeg6\teeg7\teeg8\taccel1\taccel2\taccel3\tgyro1\tgyro2\tgyro3\tbattery\tcounter\n"
        fileHandle?.write(header.data(using: .utf8)!)
    }

    func processSample(_ sample: UnicornSample) {
        let eegStr = sample.eeg.map { String(format: "%f", $0) }.joined(separator: "\t")
        let accelStr = sample.accel.map { String(format: "%f", $0) }.joined(separator: "\t")
        let gyroStr = sample.gyro.map { String(format: "%f", $0) }.joined(separator: "\t")
        let line = "\(eegStr)\t\(accelStr)\t\(gyroStr)\t\(String(format: "%.2f", sample.battery))\t\(sample.counter)\n"
        fileHandle?.write(line.data(using: .utf8)!)
    }

    func stop() {
        fileHandle?.closeFile()
        fileHandle = nil
    }
}
