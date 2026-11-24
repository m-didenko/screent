#!/bin/zsh
# Збирає Screent.app у ./build і (за бажання) запускає її.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Screent"
APP="build/Screent.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Screent"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.screent.app</string>
  <key>CFBundleName</key><string>Screent</string>
  <key>CFBundleDisplayName</key><string>Screent</string>
  <key>CFBundleExecutable</key><string>Screent</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Screent reads text from the selected screen region to translate it.</string>
</dict>
</plist>
PLIST

# Стабільний підпис: дозвіл «Запис екрана» переживає перезбирання (див. scripts/setup-signing.sh).
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning | grep -q "Screent Local Signing"; then
  IDENTITY="Screent Local Signing"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "⚠︎ Ad-hoc signature: Screen Recording access will reset after each rebuild. Run scripts/setup-signing.sh"
fi
codesign --force --sign "$IDENTITY" --identifier com.screent.app "$APP"
echo "Built: $APP"

# --install: скопіювати в /Applications (стабільний шлях — macOS краще запам'ятовує дозвіл «Запис екрана»)
if [[ " $* " == *" --install "* ]]; then
  pkill -x Screent 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Screent.app
  cp -R "$APP" /Applications/Screent.app
  APP="/Applications/Screent.app"
  echo "Installed: $APP"
fi

if [[ " $* " == *" --run "* ]]; then
  pkill -x Screent 2>/dev/null || true
  sleep 1
  open "$APP"
fi
