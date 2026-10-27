#!/usr/bin/env bash
# Renders Motu's icons and splash images into the app from the SVGs motu.py writes (M10-4). Needs
# rsvg-convert and ImageMagick.
#
#   python3 docs/brand/motu.py && docs/brand/icons.sh
set -euo pipefail
cd "$(dirname "$0")"
sea='#86D9EC'
res=../../app/android/app/src/main/res
ios=../../app/ios/Runner/Assets.xcassets

times() { awk "BEGIN { print int($1 * $2 + 0.5) }"; }
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

# Android, per density: the legacy icon (48 dp), the adaptive icon's foreground (108 dp, its background
# is @color/motu_sea), the splash island (200 dp, before Android 12).
for density in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  name=${density%%:*} scale=${density##*:}
  mkdir -p "$res/mipmap-$name" "$res/drawable-$name"
  render motu-icon.svg "$(times 48 "$scale")" "$res/mipmap-$name/ic_launcher.png"
  render motu-foreground.svg "$(times 108 "$scale")" "$res/mipmap-$name/ic_launcher_foreground.png"
  render motu-island.svg "$(times 200 "$scale")" "$res/drawable-$name/splash_island.png"
done

# iOS: every AppIcon size its file name gives (Icon-App-<points>x<points>@<scale>x.png), opaque: the App
# Store refuses an icon with an alpha channel.
for file in "$ios"/AppIcon.appiconset/Icon-App-*.png; do
  base=${file##*/Icon-App-}
  points=${base%%x*} scale=${base##*@}
  render motu-icon.svg "$(times "$points" "${scale%x.png}")" "$file"
  magick "$file" -background "$sea" -alpha remove -alpha off "$file"
done
# The launch screen's island, 200 pt (LaunchScreen.storyboard), on its sea.
render motu-island.svg 200 "$ios/LaunchImage.imageset/LaunchImage.png"
render motu-island.svg 400 "$ios/LaunchImage.imageset/LaunchImage@2x.png"
render motu-island.svg 600 "$ios/LaunchImage.imageset/LaunchImage@3x.png"
echo "icons: rendered"
