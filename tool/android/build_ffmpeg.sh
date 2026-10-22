#!/usr/bin/env bash
# Builds FFmpeg for Android as static libraries, LGPL, with MediaCodec (the
# H.264 encoder the export uses). The engine links them from FFMPEG_DIR.
#
#   tool/android/build_ffmpeg.sh <ffmpeg-source-dir> <install-prefix> [abi]
#
# `abi` is `arm64` (the default, phones and tablets) or `x86_64` (the
# emulator). Each ABI needs its own install prefix: FFMPEG_DIR points at one
# architecture, so build and run one ABI at a time.
#
# Needs the Android NDK (ANDROID_NDK_HOME, or the NDK Flutter asks for under
# ANDROID_HOME) and the FFmpeg release `ffmpeg-sys-next` expects (8.1.x),
# unpacked into an empty directory. Then build the app with
#
#   FFMPEG_DIR=<install-prefix> flutter build apk --release --target-platform android-arm64
set -euo pipefail

src=${1:?usage: build_ffmpeg.sh <ffmpeg-source-dir> <install-prefix> [arm64|x86_64]}
prefix=${2:?usage: build_ffmpeg.sh <ffmpeg-source-dir> <install-prefix> [arm64|x86_64]}
abi=${3:-arm64}
api=${ANDROID_API:-24}
ndk=${ANDROID_NDK_HOME:-${ANDROID_HOME:?set ANDROID_NDK_HOME or ANDROID_HOME}/ndk/28.2.13676358}
tc=$ndk/toolchains/llvm/prebuilt/linux-x86_64

case "$abi" in
  arm64)
    arch=aarch64
    cpu=armv8-a
    triple=aarch64-linux-android
    ;;
  x86_64)
    arch=x86_64
    cpu=x86-64
    triple=x86_64-linux-android
    # The x86 assembly is only a speed-up; it needs nasm, which the build
    # machine may not have.
    if ! command -v nasm >/dev/null; then
      asm=--disable-x86asm
      echo "nasm not found: building x86_64 without the assembly optimisations" >&2
    fi
    ;;
  *)
    echo "unknown ABI: $abi (expected arm64 or x86_64)" >&2
    exit 2
    ;;
esac

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cd "$build"
"$src/configure" \
  --prefix="$prefix" \
  --enable-cross-compile --target-os=android --arch="$arch" --cpu="$cpu" \
  --cc="$tc/bin/${triple}${api}-clang" \
  --cxx="$tc/bin/${triple}${api}-clang++" \
  --ar="$tc/bin/llvm-ar" --nm="$tc/bin/llvm-nm" \
  --ranlib="$tc/bin/llvm-ranlib" --strip="$tc/bin/llvm-strip" \
  --sysroot="$tc/sysroot" \
  ${asm:-} \
  --enable-static --disable-shared --enable-pic \
  --enable-jni --enable-mediacodec \
  --disable-programs --disable-doc --disable-avdevice --disable-avfilter \
  --disable-network --disable-debug --disable-symver \
  --extra-cflags="-O2 -fPIC"
make -j"$(nproc)"
make install
