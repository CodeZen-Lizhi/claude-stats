#!/usr/bin/env bash
# Build a macOS llama.framework from the pinned llama.cpp submodule.
set -euo pipefail
cd "$(dirname "$0")/.."

LLAMA_DIR="$PWD/ThirdParty/llama.cpp"
BUILD_DIR="$LLAMA_DIR/build-macos"
FRAMEWORK="$BUILD_DIR/framework/llama.framework"
BINARY="$FRAMEWORK/Versions/A/llama"
MIN_MACOS="${LLAMA_MIN_MACOS:-14.0}"
LLAMA_ARCHS="${LLAMA_ARCHS:-arm64}"
COMMON_C_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"
COMMON_CXX_FLAGS="-Wno-macro-redefined -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -g"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "error: Claude Stats now supports Apple Silicon only; build llama runtime on an arm64 Mac." >&2
    exit 1
fi

if [[ "$LLAMA_ARCHS" != "arm64" ]]; then
    echo "error: LLAMA_ARCHS must be arm64 for Apple Silicon-only builds (got '$LLAMA_ARCHS')" >&2
    exit 1
fi

if [[ ! -d "$LLAMA_DIR/include" ]]; then
    echo "error: llama.cpp submodule is missing at $LLAMA_DIR" >&2
    echo "hint: git submodule update --init --recursive ThirdParty/llama.cpp" >&2
    exit 1
fi

if [[ "${FORCE_LLAMA_RUNTIME_BUILD:-0}" != "1" && -x "$BINARY" ]]; then
    existing_archs="$(lipo -archs "$BINARY" 2>/dev/null | xargs || true)"
    if [[ "$existing_archs" == "arm64" ]]; then
        echo "llama runtime ready: $FRAMEWORK"
        exit 0
    fi
    echo "==> Rebuilding llama runtime; found stale architectures: ${existing_archs:-unknown}"
    rm -rf "$BUILD_DIR"
fi

command -v cmake >/dev/null 2>&1 || {
    echo "error: cmake is required to build llama.framework" >&2
    echo "hint: brew install cmake" >&2
    exit 1
}
command -v xcrun >/dev/null 2>&1 || {
    echo "error: Xcode command line tools are required to build llama.framework" >&2
    exit 1
}
CLANG="$(xcrun --find clang)"
CLANGXX="$(xcrun --find clang++)"

if [[ "${FORCE_LLAMA_RUNTIME_BUILD:-0}" == "1" ]]; then
    rm -rf "$BUILD_DIR"
elif [[ -f "$BUILD_DIR/CMakeCache.txt" && ! -x "$BINARY" ]]; then
    rm -rf "$BUILD_DIR"
fi

(
    cd "$LLAMA_DIR"

    echo "==> Configuring llama.cpp macOS runtime"
    cmake -B build-macos -G Xcode \
        -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
        -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
        -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
        -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT="dwarf-with-dsym" \
        -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
        -DCMAKE_XCODE_ATTRIBUTE_COPY_PHASE_STRIP=NO \
        -DCMAKE_XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT=NO \
        -DCMAKE_C_COMPILER="$CLANG" \
        -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLAMA_BUILD_APP=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_TOOLS=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_SERVER=OFF \
        -DLLAMA_OPENSSL=OFF \
        -DGGML_METAL=ON \
        -DGGML_METAL_EMBED_LIBRARY=ON \
        -DGGML_BLAS_DEFAULT=ON \
        -DGGML_METAL_USE_BF16=ON \
        -DGGML_NATIVE=OFF \
        -DGGML_OPENMP=OFF \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
        -DCMAKE_OSX_ARCHITECTURES="$LLAMA_ARCHS" \
        -DCMAKE_C_FLAGS="$COMMON_C_FLAGS" \
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
        -S .

    echo "==> Building llama.cpp static libraries"
    cmake --build build-macos --config Release -- -quiet

    echo "==> Creating llama.framework"
    rm -rf "$FRAMEWORK"
    mkdir -p "$FRAMEWORK/Versions/A/Headers" "$FRAMEWORK/Versions/A/Modules" "$FRAMEWORK/Versions/A/Resources"
    ln -sf A "$FRAMEWORK/Versions/Current"
    ln -sf Versions/Current/Headers "$FRAMEWORK/Headers"
    ln -sf Versions/Current/Modules "$FRAMEWORK/Modules"
    ln -sf Versions/Current/Resources "$FRAMEWORK/Resources"
    ln -sf Versions/Current/llama "$FRAMEWORK/llama"

    HEADER_DIR="$FRAMEWORK/Versions/A/Headers"
    MODULE_DIR="$FRAMEWORK/Versions/A/Modules"
    cp include/llama.h "$HEADER_DIR/"
    cp ggml/include/ggml.h "$HEADER_DIR/"
    cp ggml/include/ggml-opt.h "$HEADER_DIR/"
    cp ggml/include/ggml-alloc.h "$HEADER_DIR/"
    cp ggml/include/ggml-backend.h "$HEADER_DIR/"
    cp ggml/include/ggml-metal.h "$HEADER_DIR/"
    cp ggml/include/ggml-cpu.h "$HEADER_DIR/"
    cp ggml/include/ggml-blas.h "$HEADER_DIR/"
    cp ggml/include/gguf.h "$HEADER_DIR/"

    cat > "$MODULE_DIR/module.modulemap" <<'MODULEMAP'
framework module llama {
    header "llama.h"
    export *
    link "c++"
    link framework "Accelerate"
    link framework "Foundation"
    link framework "Metal"
}
MODULEMAP

    cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>llama</string>
    <key>CFBundleIdentifier</key>
    <string>org.ggml.llama</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>llama</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${MIN_MACOS}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>DTPlatformName</key>
    <string>macosx</string>
</dict>
</plist>
PLIST

    libs=(
        "$BUILD_DIR/src/Release/libllama.a"
        "$BUILD_DIR/ggml/src/Release/libggml.a"
        "$BUILD_DIR/ggml/src/Release/libggml-base.a"
        "$BUILD_DIR/ggml/src/Release/libggml-cpu.a"
        "$BUILD_DIR/ggml/src/ggml-metal/Release/libggml-metal.a"
        "$BUILD_DIR/ggml/src/ggml-blas/Release/libggml-blas.a"
    )
    for lib in "${libs[@]}"; do
        [[ -f "$lib" ]] || {
            echo "error: expected llama static library not found: $lib" >&2
            exit 1
        }
    done

    TEMP_DIR="$BUILD_DIR/temp-framework"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    xcrun libtool -static -o "$TEMP_DIR/combined.a" "${libs[@]}" 2>/dev/null

    arch_flags=()
    IFS=';' read -ra archs <<< "$LLAMA_ARCHS"
    for arch in "${archs[@]}"; do
        arch_flags+=(-arch "$arch")
    done

    xcrun -sdk macosx clang++ -dynamiclib \
        -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
        "${arch_flags[@]}" \
        -mmacosx-version-min="$MIN_MACOS" \
        -Wl,-force_load,"$TEMP_DIR/combined.a" \
        -framework Foundation -framework Metal -framework Accelerate \
        -install_name "@rpath/llama.framework/Versions/Current/llama" \
        -o "$BINARY"

    mkdir -p "$BUILD_DIR/dSYMs"
    xcrun dsymutil "$BINARY" -o "$BUILD_DIR/dSYMs/llama.dSYM" >/dev/null 2>&1 || true
    xcrun strip -S "$BINARY" -o "$TEMP_DIR/stripped" >/dev/null 2>&1 && mv "$TEMP_DIR/stripped" "$BINARY"
    rm -rf "$TEMP_DIR"
)

echo "==> Ready: $FRAMEWORK"
