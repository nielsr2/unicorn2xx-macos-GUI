# Building UnicornEEG GUI

## Prerequisites

### 1. Install dependencies via Homebrew

```bash
brew install libserialport portaudio libsamplerate
brew install xcodegen
```

### 2. Install liblsl

Download the latest release for macOS from:
https://github.com/sccn/liblsl/releases

Then either:
- Copy to `/usr/local/lib/liblsl.a` and `/usr/local/include/lsl_c.h`, or
- Place in the project's `external/lsl/` directory:
  ```
  external/lsl/include/lsl_c.h
  external/lsl/lib/liblsl.a
  ```

### 3. Generate the Xcode project

```bash
./setup_xcode.sh
```

This runs XcodeGen to create `UnicornEEG.xcodeproj` from `project.yml`.

### 4. Build and run

Open `UnicornEEG.xcodeproj` in Xcode, select the UnicornEEG target, and build (Cmd+B).

## Alternative: Manual Xcode project creation

If you prefer not to use XcodeGen:

1. Open Xcode → File → New → Project → macOS → App (SwiftUI)
2. Name it "UnicornEEG"
3. Add all `.swift` files from `UnicornEEG/` to the project
4. Set the bridging header in Build Settings:
   - "Objective-C Bridging Header" → `UnicornEEG/UnicornEEG-Bridging-Header.h`
5. Add Header Search Paths: `/usr/local/include` (or Homebrew prefix)
6. Add Library Search Paths: `/usr/local/lib` (or Homebrew prefix)
7. Add to "Other Linker Flags": `-lserialport -llsl -lportaudio -lsamplerate -lc++`
8. Link frameworks: CoreServices, CoreFoundation, AudioUnit, AudioToolbox, CoreAudio, IOKit
9. Disable App Sandbox in the entitlements file
10. Build and run

## Project Structure

```
UnicornEEG/
├── UnicornEEGApp.swift              — App entry point
├── UnicornEEG-Bridging-Header.h     — C library imports
├── Info.plist                       — App metadata
├── UnicornEEG.entitlements          — Sandbox disabled
├── Core/
│   ├── PacketParser.swift           — 45-byte packet decoding
│   ├── UnicornDevice.swift          — Serial port management
│   ├── StreamEngine.swift           — Background acquisition thread
│   ├── RingBuffer.swift             — Thread-safe buffer for UI
│   ├── OutputProtocol.swift         — Output sink protocol
│   ├── TextFileOutput.swift         — TSV file output
│   ├── LSLOutput.swift              — LabStreamingLayer output
│   └── AudioOutput.swift            — PortAudio + resampling output
└── Views/
    ├── ContentView.swift            — Main window layout
    ├── ConnectionView.swift         — Port picker, connect/start
    ├── WaveformView.swift           — Real-time EEG waveforms
    ├── OutputConfigView.swift       — Output mode configuration
    └── StatusBarView.swift          — Battery, counter, status
```

## Notes

- The CLI tools (`unicorn2txt`, `unicorn2lsl`, `unicorn2audio`) are unchanged and can still be built with CMake.
- The GUI app requires macOS 13.0 or later.
- If Bluetooth connection issues occur on macOS: `sudo pkill bluetoothd`
