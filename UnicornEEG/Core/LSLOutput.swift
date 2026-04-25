/*
 * LSLOutput.swift
 * UnicornEEG
 *
 * Streams EEG data to LabStreamingLayer (LSL).
 * Replaces the functionality of unicorn2lsl.
 */

import Foundation

class LSLOutput: OutputSink {
    let name = "LSL"
    var streamName: String

    private var outlet: lsl_outlet?

    init(streamName: String = "Unicorn") {
        self.streamName = streamName
    }

    func start() throws {
        let uid = randomUID(length: 8)

        let info = lsl_create_streaminfo(
            streamName,
            "EEG",
            Int32(UnicornSample.totalChannelCount),
            Double(PacketParser.sampleRate),
            cft_float32,
            uid
        )

        // Add acquisition metadata
        let desc = lsl_get_desc(info)
        let acquisition = lsl_append_child(desc, "acquisition")
        lsl_append_child_value(acquisition, "manufacturer", "Gtec")
        lsl_append_child_value(acquisition, "model", "Unicorn")
        lsl_append_child_value(acquisition, "precision", "24")

        // Add channel metadata
        let chns = lsl_append_child(desc, "channels")
        for c in 0..<UnicornSample.totalChannelCount {
            let chn = lsl_append_child(chns, "channel")
            lsl_append_child_value(chn, "label", UnicornSample.channelLabels[c])
            lsl_append_child_value(chn, "unit", UnicornSample.channelUnits[c])
            lsl_append_child_value(chn, "type", UnicornSample.channelTypes[c])
        }

        outlet = lsl_create_outlet(info, 0, 360)
        lsl_destroy_streaminfo(info)
    }

    func processSample(_ sample: UnicornSample) {
        guard let outlet = outlet else { return }
        var dat = sample.allChannels
        lsl_push_sample_f(outlet, &dat)
    }

    func stop() {
        if let outlet = outlet {
            lsl_destroy_outlet(outlet)
        }
        outlet = nil
    }

    private func randomUID(length: Int) -> String {
        let charset = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<length).map { _ in charset.randomElement()! })
    }
}
