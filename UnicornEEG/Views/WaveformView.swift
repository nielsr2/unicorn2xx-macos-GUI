/*
 * WaveformView.swift
 * UnicornEEG
 *
 * Real-time display of 8 EEG channel waveforms using Canvas + TimelineView.
 */

import SwiftUI

struct WaveformView: View {
    @EnvironmentObject var engine: StreamEngine

    @State private var displaySeconds: Double = 4.0
    @State private var amplitudeScale: Double = 100.0  // microvolts per division

    private let channelColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink
    ]

    private let channelLabels = ["EEG1", "EEG2", "EEG3", "EEG4", "EEG5", "EEG6", "EEG7", "EEG8"]

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Text("Time:")
                Slider(value: $displaySeconds, in: 1...10, step: 0.5)
                    .frame(width: 100)
                Text("\(displaySeconds, specifier: "%.1f")s")

                Spacer().frame(width: 20)

                Text("Scale:")
                Slider(value: $amplitudeScale, in: 10...500, step: 10)
                    .frame(width: 100)
                Text("\(amplitudeScale, specifier: "%.0f") \u{00B5}V")
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Waveform canvas
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                Canvas { context, size in
                    let displaySamples = Int(displaySeconds * Double(PacketParser.sampleRate))
                    let samples = engine.ringBuffer.readLatest(maxCount: displaySamples)
                    let channelCount = 8
                    let channelHeight = size.height / CGFloat(channelCount)

                    for ch in 0..<channelCount {
                        let centerY = channelHeight * (CGFloat(ch) + 0.5)

                        // Draw channel label
                        let labelText = Text(channelLabels[ch])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(channelColors[ch])
                        context.draw(labelText, at: CGPoint(x: 30, y: centerY - channelHeight * 0.35))

                        // Draw center line
                        var centerLine = Path()
                        centerLine.move(to: CGPoint(x: 0, y: centerY))
                        centerLine.addLine(to: CGPoint(x: size.width, y: centerY))
                        context.stroke(centerLine, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)

                        guard !samples.isEmpty else { continue }

                        // Draw waveform
                        var path = Path()
                        let xStep = size.width / max(1, CGFloat(displaySamples - 1))
                        let yScale = channelHeight * 0.4 / CGFloat(amplitudeScale)

                        for (i, sample) in samples.enumerated() {
                            let x = CGFloat(i) * xStep
                            let y = centerY - CGFloat(sample[ch]) * yScale

                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }

                        context.stroke(path, with: .color(channelColors[ch]), lineWidth: 1.0)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
