#!/usr/bin/env bash
# Merges the per-ABI release APKs into one universal APK that installs on a
# phone (arm64) and on an x86_64 emulator.
#
#   tool/android/universal_apk.sh <arm64.apk> <x86_64.apk> <out.apk>
#
# A single-ABI build still carries the plugins' 32-bit and x86_64 libraries
# (`libdartjni`, `libsqlite3`), so Android reports those ABIs and installs the
# APK on a device where `libflutter.so` and `libcutter_engine.so` are missing;
# the app then closes at launch. This drops the 32-bit libraries, adds the
# x86_64 engine, aligns and re-signs with the debug key (the beta key).
#
# Needs the Android build-tools: set ANDROID_HOME or pass BUILD_TOOLS.
set -euo pipefail

base=${1:?usage: universal_apk.sh <arm64.apk> <x86_64.apk> <out.apk>}
extra=${2:?usage: universal_apk.sh <arm64.apk> <x86_64.apk> <out.apk>}
out=${3:?usage: universal_apk.sh <arm64.apk> <x86_64.apk> <out.apk>}
build_tools=${BUILD_TOOLS:-${ANDROID_HOME:?set ANDROID_HOME or BUILD_TOOLS}/build-tools/36.0.0}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$base" -d "$work/base"
unzip -q "$extra" -d "$work/extra"

# 32-bit is not supported: leaving the plugins' libs in claims it is.
rm -rf "$work/base/lib/armeabi-v7a"
mkdir -p "$work/base/lib/x86_64"
cp "$work/extra/lib/x86_64/"*.so "$work/base/lib/x86_64/"

safe_out=$(readlink -f "$out")
rm -f "$safe_out" "$safe_out.aligned" "$safe_out.unsigned"
# `extractNativeLibs` is false, so the libraries must stay uncompressed and
# page-aligned in the APK, and targetSdk 30+ requires an uncompressed
# resources.arsc; everything else can be deflated.
( cd "$work/base" && zip -q -X -r "$safe_out.unsigned" . -x 'META-INF/*' 'lib/*' 'resources.arsc' )
( cd "$work/base" && zip -q -X -0 -r "$safe_out.unsigned" lib resources.arsc )
"$build_tools/zipalign" -f -p 4 "$safe_out.unsigned" "$safe_out.aligned"
"$build_tools/apksigner" sign \
  --ks "${DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}" \
  --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey \
  --out "$safe_out" "$safe_out.aligned"
rm -f "$safe_out.unsigned" "$safe_out.aligned"
"$build_tools/apksigner" verify --print-certs "$safe_out" | head -3
