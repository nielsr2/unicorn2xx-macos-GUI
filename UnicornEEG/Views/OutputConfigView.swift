/*
 * OutputConfigView.swift
 * UnicornEEG
 *
 * Toggle switches and settings for output modes:
 * text file and LSL stream.
 */

import SwiftUI

struct OutputConfigView: View {
    @EnvironmentObject var engine: StreamEngine

    // Text output
    @State private var textEnabled = false
    @State private var textFilePath = ""

    // LSL output
    @State private var lslEnabled = false
    @State private var lslStreamName = "Unicorn"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Configuration").font(.headline)

            HStack(alignment: .top, spacing: 24) {
                // Text file output
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Text File", isOn: $textEnabled)
                        .onChange(of: textEnabled) { _ in
                            updateOutputs()
                        }
                    if textEnabled {
                        HStack {
                            TextField("File path", text: $textFilePath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Button("Browse...") {
                                browseForFile()
                            }
                        }
                    }
                }
                .frame(minWidth: 200, alignment: .leading)

                Divider().frame(height: 60)

                // LSL output
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("LSL Raw EEG", isOn: $lslEnabled)
                        .onChange(of: lslEnabled) { _ in
                            updateOutputs()
                        }
                    if lslEnabled {
                        HStack {
                            Text("Name:")
                            TextField("Stream name", text: $lslStreamName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }

                    Toggle("LSL Band Power", isOn: $engine.bandPowerLSLEnabled)
                }
                .frame(minWidth: 200, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        .disabled(engine.isStreaming)
    }

    private func updateOutputs() {
        engine.removeAllOutputs()

        if textEnabled && !textFilePath.isEmpty {
            engine.addOutput(TextFileOutput(filePath: textFilePath))
        }

        if lslEnabled {
            engine.addOutput(LSLOutput(streamName: lslStreamName))
        }
    }

    private func browseForFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "unicorn_data.txt"
        if panel.runModal() == .OK, let url = panel.url {
            textFilePath = url.path
            updateOutputs()
        }
    }
}
