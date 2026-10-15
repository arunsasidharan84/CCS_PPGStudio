#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --manifest-path rust/Cargo.toml --release --target aarch64-apple-ios
FRAMEWORK=ios/Frameworks/sensio_ppg_core/libsensio_ppg_core.framework
mkdir -p "$FRAMEWORK"
cp rust/target/aarch64-apple-ios/release/libsensio_ppg_core.dylib "$FRAMEWORK/libsensio_ppg_core"
install_name_tool -id @rpath/libsensio_ppg_core.framework/libsensio_ppg_core "$FRAMEWORK/libsensio_ppg_core"
cat > "$FRAMEWORK/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.ccs.ppgstudio.core</string>
<key>CFBundleName</key><string>libsensio_ppg_core</string>
<key>CFBundleExecutable</key><string>libsensio_ppg_core</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>MinimumOSVersion</key><string>15.0</string>
</dict></plist>
PLIST
cat > ios/Frameworks/sensio_ppg_core/sensio_ppg_core.podspec <<'SPEC'
Pod::Spec.new do |s|
  s.name = 'sensio_ppg_core'
  s.version = '1.1.0'
  s.summary = 'CCS PPG native analysis engine'
  s.homepage = 'https://github.com/arunsasidharan84/CCS_PPGStudio'
  s.author = { 'CCS' => 'info@sensio-ai.in' }
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'libsensio_ppg_core.framework'
end
SPEC
cp rust/target/aarch64-apple-ios/release/libsensio_ppg_core.a ios/Frameworks/
