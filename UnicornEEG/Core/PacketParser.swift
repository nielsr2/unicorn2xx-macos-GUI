/*
 * PacketParser.swift
 * UnicornEEG
 *
 * Decodes 45-byte binary packets from the Unicorn Hybrid Black EEG device.
 *
 * Packet format:
 *   Bytes 0-1:   Start sequence (0xC0, 0x00)
 *   Byte 2:      Battery level (lower 4 bits, 0-15 → 0-100%)
 *   Bytes 3-26:  8 EEG channels (3 bytes each, 24-bit signed)
 *   Bytes 27-32: 3 accelerometer channels (2 bytes each, 16-bit signed)
 *   Bytes 33-38: 3 gyroscope channels (2 bytes each, 16-bit signed)
 *   Bytes 39-42: Sample counter (4 bytes, little-endian unsigned)
 *   Bytes 43-44: Stop sequence (0x0D, 0x0A)
 */

import Foundation

struct UnicornSample {
    let eeg: [Float]      // 8 channels, microvolts
    let accel: [Float]    // 3 channels, g
    let gyro: [Float]     // 3 channels, deg/s
    let battery: Float    // 0-100%
    let counter: UInt32

    static let eegChannelCount = 8
    static let accelChannelCount = 3
    static let gyroChannelCount = 3
    static let totalChannelCount = 16

    static let channelLabels = [
        "eeg1", "eeg2", "eeg3", "eeg4", "eeg5", "eeg6", "eeg7", "eeg8",
        "accelX", "accelY", "accelZ",
        "gyroX", "gyroY", "gyroZ",
        "battery", "counter"
    ]

    static let channelUnits = [
        "uV", "uV", "uV", "uV", "uV", "uV", "uV", "uV",
        "g", "g", "g",
        "deg/s", "deg/s", "deg/s",
        "percent", "integer"
    ]

    static let channelTypes = [
        "EEG", "EEG", "EEG", "EEG", "EEG", "EEG", "EEG", "EEG",
        "ACCEL", "ACCEL", "ACCEL",
        "GYRO", "GYRO", "GYRO",
        "BATTERY", "COUNTER"
    ]

    /// All 16 channels as a flat float array (for LSL output compatibility)
    var allChannels: [Float] {
        var dat = [Float](repeating: 0, count: 16)
        for i in 0..<8 { dat[i] = eeg[i] }
        for i in 0..<3 { dat[8 + i] = accel[i] }
        for i in 0..<3 { dat[11 + i] = gyro[i] }
        dat[14] = battery
        dat[15] = Float(counter)
        return dat
    }
}

enum PacketParser {
    static let packetSize = 45
    static let sampleRate = 250

    static func parse(_ buf: UnsafePointer<UInt8>) -> UnicornSample? {
        // Validate start sequence
        guard buf[0] == 0xC0, buf[1] == 0x00 else { return nil }

        // Battery: lower 4 bits of byte 2
        let battery = Float(buf[2] & 0x0F) * 100.0 / 15.0

        // 8 EEG channels: 3 bytes each, 24-bit signed, starting at byte 3
        var eeg = [Float](repeating: 0, count: 8)
        for ch in 0..<8 {
            var val = UInt32(buf[3 + ch * 3]) << 16 | UInt32(buf[4 + ch * 3]) << 8 | UInt32(buf[5 + ch * 3])
            // Sign-extend 24-bit to 32-bit
            if val & 0x00800000 != 0 {
                val |= 0xFF000000
            }
            eeg[ch] = Float(Int32(bitPattern: val)) * 4500000.0 / 50331642.0
        }

        // 3 accelerometer channels: 2 bytes each, 16-bit signed LE, starting at byte 27
        var accel = [Float](repeating: 0, count: 3)
        for ch in 0..<3 {
            let val = Int16(buf[27 + ch * 2]) | Int16(buf[28 + ch * 2]) << 8
            accel[ch] = Float(val) / 4096.0
        }

        // 3 gyroscope channels: 2 bytes each, 16-bit signed LE, starting at byte 33
        var gyro = [Float](repeating: 0, count: 3)
        for ch in 0..<3 {
            let val = Int16(buf[33 + ch * 2]) | Int16(buf[34 + ch * 2]) << 8
            gyro[ch] = Float(val) / 32.8
        }

        // Counter: 4 bytes, little-endian unsigned, starting at byte 39
        let counter = UInt32(buf[39]) | UInt32(buf[40]) << 8 | UInt32(buf[41]) << 16 | UInt32(buf[42]) << 24

        return UnicornSample(eeg: eeg, accel: accel, gyro: gyro, battery: battery, counter: counter)
    }
}
