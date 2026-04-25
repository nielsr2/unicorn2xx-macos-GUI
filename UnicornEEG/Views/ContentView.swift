/*
 * ContentView.swift
 * UnicornEEG
 *
 * Main window layout: connection controls at top, waveform center, status bar bottom.
 */

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: StreamEngine

    var body: some View {
        VStack(spacing: 0) {
            ConnectionView()
                .padding()

            Divider()

            WaveformView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            OutputConfigView()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            StatusBarView()
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("Error", isPresented: .init(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )) {
            Button("OK") { engine.errorMessage = nil }
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }
}
