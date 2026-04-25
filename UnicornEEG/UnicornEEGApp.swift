/*
 * UnicornEEGApp.swift
 * UnicornEEG
 *
 * Main entry point for the Unicorn EEG macOS GUI application.
 */

import SwiftUI

@main
struct UnicornEEGApp: App {
    @StateObject private var engine = StreamEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
        .defaultSize(width: 1000, height: 700)
    }
}
