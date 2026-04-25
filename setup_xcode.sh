#!/bin/bash
#
# Setup script for UnicornEEG macOS GUI application.
#
# This script:
# 1. Checks that required dependencies are installed (via Homebrew)
# 2. Generates the Xcode project using XcodeGen
#
# Prerequisites:
#   brew install libserialport portaudio libsamplerate
#   brew install xcodegen
#
# For liblsl, download from:
#   https://github.com/sccn/liblsl/releases
# and place in external/lsl/{include,lib}
#

set -e

echo "=== UnicornEEG Xcode Project Setup ==="
echo

# Check for XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

# Check for required libraries
MISSING=""
for lib in serialport portaudio samplerate; do
    if [ ! -f "/usr/local/lib/lib${lib}.a" ] && [ ! -f "/opt/homebrew/lib/lib${lib}.a" ]; then
        if [ ! -f "external/${lib}/lib/lib${lib}.a" ]; then
            MISSING="${MISSING} lib${lib}"
        fi
    fi
done

if [ -n "$MISSING" ]; then
    echo "WARNING: Missing libraries:${MISSING}"
    echo "Install with: brew install libserialport portaudio libsamplerate"
    echo
fi

# Check for liblsl
if [ ! -f "/usr/local/lib/liblsl.a" ] && [ ! -f "/opt/homebrew/lib/liblsl.a" ] && [ ! -f "external/lsl/lib/liblsl.a" ]; then
    echo "WARNING: liblsl not found."
    echo "Download from: https://github.com/sccn/liblsl/releases"
    echo "Place headers in: external/lsl/include/"
    echo "Place library in: external/lsl/lib/"
    echo
fi

# Detect Homebrew prefix and update project.yml if on Apple Silicon
BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/usr/local")
if [ "$BREW_PREFIX" != "/usr/local" ]; then
    echo "Detected Homebrew at: $BREW_PREFIX"
    echo "Updating library search paths..."
    sed -i '' "s|/usr/local/include|${BREW_PREFIX}/include|g" project.yml
    sed -i '' "s|/usr/local/lib|${BREW_PREFIX}/lib|g" project.yml
fi

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

echo
echo "=== Done! ==="
echo "Open UnicornEEG.xcodeproj in Xcode and build."
echo
