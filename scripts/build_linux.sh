#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --manifest-path rust/Cargo.toml --release
flutter build linux --release
mkdir -p dist/CCSPPGStudio
cp -a build/linux/x64/release/bundle/. dist/CCSPPGStudio/
cp rust/target/release/libsensio_ppg_core.so dist/CCSPPGStudio/lib/
tar -czf dist/CCSPPGStudio-Linux-x64.tar.gz -C dist CCSPPGStudio
