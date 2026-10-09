#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🍏 Building Sensio PPG Studio for macOS"
echo "=================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔨 [1/4] Compiling Rust native engine (universal aarch64 + x86_64)..."
cd rust
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
cd ..

echo "📦 [2/4] Staging universal macOS dynamic library with rpath ID..."
mkdir -p macos/Frameworks bin
lipo -create \
  rust/target/aarch64-apple-darwin/release/libsensio_ppg_core.dylib \
  rust/target/x86_64-apple-darwin/release/libsensio_ppg_core.dylib \
  -output macos/Frameworks/libsensio_ppg_core.dylib
install_name_tool -id @rpath/libsensio_ppg_core.dylib macos/Frameworks/libsensio_ppg_core.dylib
cp macos/Frameworks/libsensio_ppg_core.dylib bin/libsensio_ppg_core.dylib

echo "🚀 [3/4] Building Flutter macOS application..."
flutter build macos --release

echo "🔒 [4/4] Injecting native engine & codesigning app bundle..."
APP="build/macos/Build/Products/Release/CCS PPG Studio.app"
mkdir -p "$APP/Contents/Frameworks"
cp macos/Frameworks/libsensio_ppg_core.dylib "$APP/Contents/Frameworks/libsensio_ppg_core.dylib"

SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Apple Development: [^"]*' | head -n 1 || true)
if [ -n "$SIGN_IDENTITY" ]; then
  echo "Signing with identity: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libsensio_ppg_core.dylib"
  codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements macos/Runner/Release.entitlements "$APP"
else
  codesign --force --sign - "$APP/Contents/Frameworks/libsensio_ppg_core.dylib"
  codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$APP"
fi

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/CCSPPGStudio-macos.zip

echo "=================================================="
echo "✅ macOS build completed: dist/CCSPPGStudio-macos.zip"
echo "=================================================="
