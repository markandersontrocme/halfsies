#!/bin/sh
# Renders social-preview.svg to social-preview.png with headless Chrome, which draws the macOS system font.
# Upload the PNG in the repository's Settings > General > Social preview.
set -eu
cd "$(dirname "$0")"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --hide-scrollbars \
  --window-size=1280,640 --screenshot="$PWD/social-preview.png" "$PWD/social-preview.svg" 2>/dev/null
