/*
 * StatusBarView.swift
 * UnicornEEG
 *
 * Displays battery level, sample counter, and connection status.
 */

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var engine: StreamEngine

    var body: some View {
        HStack(spacing: 16) {
            // Connection indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }

            Divider().frame(height: 16)

            // Battery
            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                Text("\(engine.batteryLevel, specifier: "%.0f")%")
            }

            Divider().frame(height: 16)

            // Sample counter
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("\(engine.sampleCount) samples")
            }

            if engine.sampleCount > 0 {
                Text("(\(String(format: "%.1f", Double(engine.sampleCount) / Double(PacketParser.sampleRate)))s)")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Unicorn Hybrid Black — 250 Hz, 8ch EEG")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11))
    }

    private var statusColor: Color {
        if engine.isStreaming { return .green }
        if engine.isResettingBluetooth { return .yellow }
        if engine.isConnected { return .orange }
        return .red
    }

    private var statusText: String {
        if engine.isStreaming { return "Streaming" }
        if engine.isResettingBluetooth { return "Resetting Bluetooth..." }
        if engine.isConnected { return "Connected" }
        return "Disconnected"
    }

    private var batteryIcon: String {
        let level = engine.batteryLevel
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        if level > 0 { return "battery.25" }
        return "battery.0"
    }
}
