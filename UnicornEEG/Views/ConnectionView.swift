/*
 * ConnectionView.swift
 * UnicornEEG
 *
 * Port selection and start/stop streaming controls.
 */

import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var engine: StreamEngine
    @State private var ports: [SerialPortInfo] = []
    @State private var selectedPortName: String = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Port picker
                Picker("Port:", selection: $selectedPortName) {
                    if ports.isEmpty {
                        Text("No ports found").tag("")
                    }
                    ForEach(ports, id: \.name) { port in
                        Text("\(port.name) — \(port.description)")
                            .tag(port.name)
                    }
                }
                .frame(minWidth: 300)
                .disabled(engine.isStreaming || engine.isResettingBluetooth)

                Button(action: refreshPorts) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(engine.isStreaming || engine.isResettingBluetooth)
                .help("Refresh port list")

                Spacer()

                // Start / Stop streaming
                if engine.isStreaming {
                    Button("Stop") {
                        engine.stopStreaming()
                    }
                    .tint(.orange)
                } else if engine.isResettingBluetooth {
                    Button("Connecting...") {}
                        .disabled(true)
                } else {
                    Button("Start") {
                        engine.connectAndStream()
                    }
                }
            }

            // Bluetooth reset progress
            if engine.isResettingBluetooth, let message = engine.bluetoothStatusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            refreshPorts()
        }
    }

    private func refreshPorts() {
        ports = UnicornDevice.listPorts()
        if let unicorn = ports.first(where: { $0.isUnicorn }) {
            selectedPortName = unicorn.name
        } else if let first = ports.first {
            selectedPortName = first.name
        } else {
            selectedPortName = ""
        }
    }
}
