#!/usr/bin/env bash
# Regenerates every brand PNG from assets/brand/*.svg (spec §3.2).
# Requires ImageMagick 7 (`magick`). Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/../.."

B=assets/brand
I=assets/icon
BLUE='#3E7CB1'
CREAM='#F7F2EA'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# High density so curves rasterise smoothly before downscaling.
render() { magick -background none -density 1200 "$1" -resize "$2" "$3"; }

# 1. iOS/launcher master: full icon, opaque, 1024.
render "$B/busboard_icon.svg" 1024x1024 "$TMP/icon.png"
magick "$TMP/icon.png" -background "$BLUE" -alpha remove -alpha off "$I/app_icon.png"

# 2. Android adaptive foreground: mark at ~60% of a 1024 transparent canvas
#    (inside the 66% safe zone).
render "$B/busboard_mark.svg" 600x600 "$TMP/mark600.png"
magick -size 1024x1024 xc:none "$TMP/mark600.png" -gravity center -composite "$I/app_icon_foreground.png"

# 3. Splash logo (iOS + pre-12 Android): mark on transparent 768.
render "$B/busboard_mark.svg" 768x768 "$TMP/mark768.png"
magick -size 768x768 xc:none "$TMP/mark768.png" -gravity center -composite "$I/splash_logo.png"

# 4. Android 12 splash: 1152 canvas, content inside the 768 circle.
render "$B/busboard_mark.svg" 560x560 "$TMP/mark560.png"
magick -size 1152x1152 xc:none "$TMP/mark560.png" -gravity center -composite "$I/splash_logo_android12.png"

# 5. Play Store icon 512.
magick "$I/app_icon.png" -resize 512x512 "$I/app_icon_gplay.png"

# 6. Play feature graphic 1024x500: mark left, wordmark right.
render "$B/busboard_mark.svg" 340x340 "$TMP/mark340.png"
magick -size 1024x500 "xc:$BLUE" \
  "$TMP/mark340.png" -gravity west -geometry +80+0 -composite \
  -fill "$CREAM" -gravity west \
  -font assets/fonts/Figtree-ExtraBold.ttf -pointsize 88 -annotate +460-24 'BusBoard NL' \
  -font assets/fonts/Figtree-SemiBold.ttf -pointsize 34 -annotate +464+56 "Live arrivals for St. John's buses" \
  "$I/feature_graph_gplay.png"

magick identify "$I/app_icon.png" "$I/app_icon_foreground.png" "$I/splash_logo.png" \
  "$I/splash_logo_android12.png" "$I/app_icon_gplay.png" "$I/feature_graph_gplay.png"
