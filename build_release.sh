#!/bin/bash
#
# Build universal release of UnicornEEG.
#
# This script:
# 1. Downloads and compiles libserialport as a universal (x86_64 + arm64) dylib
# 2. Copies the universal liblsl from /Library/Frameworks
# 3. Builds the app for both architectures
# 4. Bundles all dylibs into the .app and fixes load paths
# 5. Creates two zip archives: one for Intel, one for Apple Silicon
#

set -e

# Ensure autotools gnubin paths are available (Homebrew installs with g- prefix)
export PATH="/usr/local/opt/libtool/libexec/gnubin:/usr/local/opt/autoconf/bin:/usr/local/opt/automake/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/release_build"
DEPS_DIR="$BUILD_DIR/deps"
DEPS_UNIVERSAL="$DEPS_DIR/universal"
PRODUCT_DIR="$BUILD_DIR/products"

echo "=== UnicornEEG Release Build ==="
echo

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$DEPS_DIR/src" "$DEPS_UNIVERSAL/lib" "$DEPS_UNIVERSAL/include" "$PRODUCT_DIR"

# ---------------------------------------------------------------------------
# Step 1: Build universal dylibs
# ---------------------------------------------------------------------------

ARCHS="x86_64 arm64"
SDK=$(xcrun --show-sdk-path)
MIN_VERSION="15.0"
COMMON_CFLAGS="-isysroot $SDK -mmacosx-version-min=$MIN_VERSION"

build_autotools_universal() {
    local name=$1 url=$2 configure_args=$3
    echo "--- Building $name (universal) ---"
    cd "$DEPS_DIR/src"

    if [ ! -d "$name" ]; then
        git clone --depth 1 "$url" "$name"
    fi

    for arch in $ARCHS; do
        echo "  [$arch]"
        local build_dir="$DEPS_DIR/build-${name}-${arch}"
        rm -rf "$build_dir"
        mkdir -p "$build_dir"

        cd "$DEPS_DIR/src/$name"

        # Generate configure if needed
        if [ ! -f configure ]; then
            if [ -f autogen.sh ]; then
                ./autogen.sh 2>/dev/null
            elif [ -f configure.ac ]; then
                autoreconf -fi 2>/dev/null
            fi
        fi

        local host
        if [ "$arch" = "arm64" ]; then
            host="aarch64-apple-darwin"
        else
            host="x86_64-apple-darwin"
        fi

        ./configure \
            --prefix="$build_dir/install" \
            --host="$host" \
            --disable-static \
            --enable-shared \
            CC="clang -arch $arch" \
            CFLAGS="$COMMON_CFLAGS" \
            LDFLAGS="-arch $arch -isysroot $SDK -mmacosx-version-min=$MIN_VERSION" \
            $configure_args \
            > "$build_dir/configure.log" 2>&1

        make -j$(sysctl -n hw.ncpu) > "$build_dir/build.log" 2>&1
        make install > "$build_dir/install.log" 2>&1
        make clean > /dev/null 2>&1 || true
    done

    cd "$DEPS_DIR"
}

lipo_merge() {
    local name=$1 dylib=$2
    echo "  Merging $dylib into universal binary"
    local x86="$DEPS_DIR/build-${name}-x86_64/install/lib/$dylib"
    local arm="$DEPS_DIR/build-${name}-arm64/install/lib/$dylib"
    lipo -create "$x86" "$arm" -output "$DEPS_UNIVERSAL/lib/$dylib"

    # Copy headers from one arch (they're the same)
    cp -R "$DEPS_DIR/build-${name}-x86_64/install/include/"* "$DEPS_UNIVERSAL/include/" 2>/dev/null || true
}

# libserialport
build_autotools_universal "libserialport" "https://github.com/sigrokproject/libserialport.git"
lipo_merge "libserialport" "libserialport.0.dylib"

# liblsl — already universal in /Library/Frameworks
echo "--- Copying liblsl (already universal) ---"
cp /Library/Frameworks/lsl.framework/Versions/A/lsl "$DEPS_UNIVERSAL/lib/liblsl.dylib"
cp -R /Library/Frameworks/lsl.framework/Versions/A/include/* "$DEPS_UNIVERSAL/include/"

# Create linker symlinks (ld looks for libfoo.dylib, not libfoo.0.dylib)
cd "$DEPS_UNIVERSAL/lib"
ln -sf libserialport.0.dylib libserialport.dylib

# Create a minimal lsl.framework structure so -framework lsl works
LSL_FW="$DEPS_UNIVERSAL/frameworks/lsl.framework/Versions/A"
mkdir -p "$LSL_FW"
cp "$DEPS_UNIVERSAL/lib/liblsl.dylib" "$LSL_FW/lsl"
ln -sf Versions/A "$DEPS_UNIVERSAL/frameworks/lsl.framework/Current"
ln -sf Versions/A/lsl "$DEPS_UNIVERSAL/frameworks/lsl.framework/lsl"

echo
echo "Verifying universal binaries:"
for f in "$DEPS_UNIVERSAL/lib/"*.dylib; do
    echo "  $(basename "$f"): $(lipo -info "$f" 2>&1)"
done

# ---------------------------------------------------------------------------
# Step 2: Build the app for each architecture
# ---------------------------------------------------------------------------

cd "$SCRIPT_DIR"

for arch in x86_64 arm64; do
    echo
    echo "=== Building UnicornEEG ($arch) ==="

    ARCH_DIR="$PRODUCT_DIR/$arch"
    mkdir -p "$ARCH_DIR"

    xcodebuild \
        -project UnicornEEG.xcodeproj \
        -scheme UnicornEEG \
        -configuration Release \
        -arch "$arch" \
        HEADER_SEARCH_PATHS="$DEPS_UNIVERSAL/include /Library/Frameworks/lsl.framework/Versions/A/include" \
        LIBRARY_SEARCH_PATHS="$DEPS_UNIVERSAL/lib" \
        FRAMEWORK_SEARCH_PATHS="$DEPS_UNIVERSAL/frameworks /Library/Frameworks" \
        CONFIGURATION_BUILD_DIR="$ARCH_DIR" \
        CODE_SIGN_IDENTITY="-" \
        > "$ARCH_DIR/build.log" 2>&1

    APP="$ARCH_DIR/UnicornEEG.app"

    if [ ! -d "$APP" ]; then
        echo "ERROR: Build failed for $arch. Check $ARCH_DIR/build.log"
        exit 1
    fi

    # -----------------------------------------------------------------------
    # Step 3: Bundle dylibs and fix load paths
    # -----------------------------------------------------------------------

    echo "  Bundling dylibs..."
    FRAMEWORKS_DIR="$APP/Contents/Frameworks"
    mkdir -p "$FRAMEWORKS_DIR"

    # Extract the single-arch slice for each dylib
    lipo "$DEPS_UNIVERSAL/lib/libserialport.0.dylib" -thin "$arch" -output "$FRAMEWORKS_DIR/libserialport.0.dylib"
    lipo "$DEPS_UNIVERSAL/lib/liblsl.dylib" -thin "$arch" -output "$FRAMEWORKS_DIR/liblsl.dylib"

    echo "  Fixing load paths..."

    # Fix each dylib's install name
    install_name_tool -id @executable_path/../Frameworks/libserialport.0.dylib "$FRAMEWORKS_DIR/libserialport.0.dylib"
    install_name_tool -id @executable_path/../Frameworks/liblsl.dylib "$FRAMEWORKS_DIR/liblsl.dylib"

    # Fix references in all binaries in MacOS/
    for binary in "$APP/Contents/MacOS/"*; do
        [ -f "$binary" ] || continue
        refs=$(otool -L "$binary" | tail -n +2 | awk '{print $1}')
        for path in $refs; do
            base=$(basename "$path")
            new=""
            case "$base" in
                libserialport*) new="@executable_path/../Frameworks/libserialport.0.dylib" ;;
                lsl|liblsl*) new="@executable_path/../Frameworks/liblsl.dylib" ;;
            esac
            if [ -n "$new" ] && [ "$path" != "$new" ]; then
                install_name_tool -change "$path" "$new" "$binary" 2>/dev/null || true
            fi
        done
    done

    # Ad-hoc sign everything
    for dylib in "$FRAMEWORKS_DIR/"*.dylib; do
        codesign --force --sign - "$dylib" 2>/dev/null
    done
    codesign --force --sign - "$APP"

    echo "  Verifying bundled libs:"
    otool -L "$APP/Contents/MacOS/"* | grep "@executable_path" | sed 's/^/    /'

    # -----------------------------------------------------------------------
    # Step 4: Package
    # -----------------------------------------------------------------------

    if [ "$arch" = "x86_64" ]; then
        ZIPNAME="UnicornEEG-macOS-Intel.zip"
    else
        ZIPNAME="UnicornEEG-macOS-AppleSilicon.zip"
    fi

    echo "  Creating $ZIPNAME..."
    cd "$ARCH_DIR"
    ditto -c -k --keepParent UnicornEEG.app "$PRODUCT_DIR/$ZIPNAME"
    cd "$SCRIPT_DIR"
done

echo
echo "=== Release builds complete ==="
echo "Output:"
ls -lh "$PRODUCT_DIR/"*.zip
