# Building from source

## Requirements

- macOS 15.0 or later
- Xcode
- [Homebrew](https://brew.sh)

## Dependencies

Install via Homebrew:

```bash
brew install libserialport xcodegen
```

Install [liblsl](https://github.com/sccn/liblsl/releases) manually — download the latest release and copy the files:

```bash
# Option A: system-wide
cp liblsl/lib/* /usr/local/lib/
cp liblsl/include/* /usr/local/include/

# Option B: project-local
mkdir -p external/lsl/{lib,include}
cp liblsl/lib/* external/lsl/lib/
cp liblsl/include/* external/lsl/include/
```

## Build and run

```bash
./setup_xcode.sh       # generates the Xcode project via XcodeGen
open UnicornEEG.xcodeproj
```

Build with **Cmd+B** in Xcode and run.

> **Note:** The App Sandbox must be disabled for Bluetooth and serial port access.

## Release builds

To build self-contained `.app` bundles for both Intel and Apple Silicon (with all dylibs bundled):

```bash
brew install autoconf automake libtool   # needed to compile deps from source
./build_release.sh
```

This cross-compiles libserialport as a universal binary, copies liblsl, builds the app for both architectures, bundles everything into the `.app`, and creates two zip files in `release_build/products/`.

## Dependencies overview

| Library | Purpose |
|---------|---------|
| [libserialport](https://sigrok.org/wiki/Libserialport) | Serial port communication |
| [liblsl](https://labstreaminglayer.readthedocs.io) | LabStreamingLayer streaming |
| [blueutil](https://github.com/toy/blueutil) | Bluetooth CLI control (bundled in Resources) |
