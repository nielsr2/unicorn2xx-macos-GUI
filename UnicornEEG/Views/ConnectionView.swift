/*
 * ConnectionView.swift
 * UnicornEEG
 *
 * Port selection dropdown, connect/disconnect, and start/stop streaming controls.
 */

import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var engine: StreamEngine
    @State private var ports: [SerialPortInfo] = []
    @State private var selectedPortName: String = ""

    var body: some View {
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
            .disabled(engine.isConnected)

            Button(action: refreshPorts) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(engine.isConnected)
            .help("Refresh port list")

            Spacer()

            // Connect / Disconnect
            if engine.isConnected {
                Button("Disconnect") {
                    engine.disconnect()
                }
                .tint(.red)
            } else {
                Button("Connect") {
                    guard !selectedPortName.isEmpty else { return }
                    engine.connect(portName: selectedPortName)
                }
                .disabled(selectedPortName.isEmpty)
            }

            // Start / Stop streaming
            if engine.isStreaming {
                Button("Stop") {
                    engine.stopStreaming()
                }
                .tint(.orange)
            } else {
                Button("Start") {
                    engine.startStreaming()
                }
                .disabled(!engine.isConnected)
            }
        }
        .onAppear {
            refreshPorts()
        }
    }

    private func refreshPorts() {
        ports = UnicornDevice.listPorts()
        // Auto-select first Unicorn device, or first port
        if let unicorn = ports.first(where: { $0.isUnicorn }) {
            selectedPortName = unicorn.name
        } else if let first = ports.first {
            selectedPortName = first.name
        } else {
            selectedPortName = ""
        }
    }
}
