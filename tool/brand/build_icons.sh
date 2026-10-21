#!/usr/bin/env bash
# Renders the brand SVGs in assets/brand/ into every platform's icon and
# splash assets. Needs rsvg-convert. Run from anywhere: tool/brand/build_icons.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
brand="$root/assets/brand"
res="$root/android/app/src/main/res"
render() { rsvg-convert -w "$1" -h "$1" "${@:3}" -o "$2"; }

# Android legacy launcher (square, rounded by the launcher) and adaptive layers.
declare -A legacy=([mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192)
declare -A layer=([mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432)
for d in "${!legacy[@]}"; do
  render "${legacy[$d]}" "$res/mipmap-$d/ic_launcher.png" "$brand/app_icon.svg"
  render "${layer[$d]}" "$res/mipmap-$d/ic_launcher_foreground.png" "$brand/icon_foreground.svg"
  render "${layer[$d]}" "$res/mipmap-$d/ic_launcher_monochrome.png" "$brand/icon_monochrome.svg"
done

# Linux window and bundle icon, plus a general-purpose PNG set.
mkdir -p "$root/linux/runner/resources"
render 512 "$root/linux/runner/resources/cutter.png" "$brand/app_icon.svg"

# iOS: opaque, full-bleed (the system applies the mask).
icons="$root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for f in "$icons"/Icon-App-*.png; do
  n="$(basename "$f" .png)"; base="${n#Icon-App-}"; size="${base%%@*}"
  scale="${base##*@}"; scale="${scale%x}"
  px="$(awk -v s="${size%%x*}" -v k="$scale" 'BEGIN{printf "%d", s*k+0.5}')"
  render "$px" "$f" "$brand/app_icon.svg"
done
# iOS launch screen: the 108pt foreground (mark is 52pt) over the brand color
# set in LaunchScreen.storyboard.
launch="$root/ios/Runner/Assets.xcassets/LaunchImage.imageset"
render 108 "$launch/LaunchImage.png" "$brand/icon_foreground.svg"
render 216 "$launch/LaunchImage@2x.png" "$brand/icon_foreground.svg"
render 324 "$launch/LaunchImage@3x.png" "$brand/icon_foreground.svg"
echo "icons rendered"
