#!/usr/bin/env bash
# Builds FFmpeg for Android arm64 as static libraries, LGPL, with MediaCodec
# (the H.264 encoder the export uses). The engine links them from FFMPEG_DIR.
#
#   tool/android/build_ffmpeg.sh <ffmpeg-source-dir> <install-prefix>
#
# Needs the Android NDK (ANDROID_NDK_HOME, or the NDK Flutter asks for under
# ANDROID_HOME) and the FFmpeg release `ffmpeg-sys-next` expects (8.1.x),
# unpacked into an empty directory. Then build the app with
#
#   FFMPEG_DIR=<install-prefix> flutter build apk --release --target-platform android-arm64
set -euo pipefail

src=${1:?usage: build_ffmpeg.sh <ffmpeg-source-dir> <install-prefix>}
prefix=${2:?usage: build_ffmpeg.sh <ffmpeg-source-dir> <install-prefix>}
api=${ANDROID_API:-24}
ndk=${ANDROID_NDK_HOME:-${ANDROID_HOME:?set ANDROID_NDK_HOME or ANDROID_HOME}/ndk/28.2.13676358}
tc=$ndk/toolchains/llvm/prebuilt/linux-x86_64

build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cd "$build"
"$src/configure" \
  --prefix="$prefix" \
  --enable-cross-compile --target-os=android --arch=aarch64 --cpu=armv8-a \
  --cc="$tc/bin/aarch64-linux-android${api}-clang" \
  --cxx="$tc/bin/aarch64-linux-android${api}-clang++" \
  --ar="$tc/bin/llvm-ar" --nm="$tc/bin/llvm-nm" \
  --ranlib="$tc/bin/llvm-ranlib" --strip="$tc/bin/llvm-strip" \
  --sysroot="$tc/sysroot" \
  --enable-static --disable-shared --enable-pic \
  --enable-jni --enable-mediacodec \
  --disable-programs --disable-doc --disable-avdevice --disable-avfilter \
  --disable-network --disable-debug --disable-symver \
  --extra-cflags="-O2 -fPIC"
make -j"$(nproc)"
make install
