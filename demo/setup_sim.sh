#!/usr/bin/env bash
# Create (once), boot, and dress the demo Simulator: dark mode, clean status bar,
# on-screen keyboard with autocorrect and predictions off. Optionally builds and
# installs the Debug Simulator app. Prints the device UDID on the last line.
#
#   demo/setup_sim.sh            # setup + build + install
#   demo/setup_sim.sh --no-build # setup only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_NAME="${DEMO_DEVICE_NAME:-Angles Demo iPhone 17 Pro}"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME="${DEMO_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
BUILD=1
[[ "${1:-}" == "--no-build" ]] && BUILD=0

log() { echo "[setup_sim] $*" >&2; }

udid="$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"]); sys.exit(0)
' "$DEVICE_NAME" || true)"

if [[ -z "$udid" ]]; then
  log "creating $DEVICE_NAME"
  udid="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")"
fi
log "device $udid"

# The software keyboard only shows when the Mac keyboard is not attached to the Simulator.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

state="$(xcrun simctl list devices | rg -F "$udid" | rg -o '\((Booted|Shutdown)\)' || true)"
if [[ "$state" != "(Booted)" ]]; then
  log "booting"
  xcrun simctl boot "$udid"
fi
xcrun simctl bootstatus "$udid" -b >/dev/null

# en_US so the status bar reads 9:41 and the keyboard is the US layout.
if [[ "$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2>/dev/null || true)" != "en_US" ]]; then
  log "setting en_US locale (reboot)"
  xcrun simctl spawn "$udid" defaults write -g AppleLocale -string en_US
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array en-US
  xcrun simctl shutdown "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
fi

xcrun simctl ui "$udid" appearance dark
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3

# Typed text must arrive exactly as written, and no first-use keyboard tips.
for key in KeyboardAutocorrection KeyboardPrediction KeyboardShowPredictionBar \
  KeyboardCheckSpelling KeyboardSmartPunctuation; do
  xcrun simctl spawn "$udid" defaults write com.apple.Preferences "$key" -bool NO
done
for key in DidShowContinuousPathIntroduction DidShowGestureKeyboardIntroduction \
  KeyboardDidShowProductivityTutorial; do
  xcrun simctl spawn "$udid" defaults write com.apple.Preferences "$key" -bool YES
done

if [[ "$BUILD" == 1 ]]; then
  log "building Debug for the Simulator"
  (
    cd "$ROOT/AnglesApp"
    xcodebuild -project AnglesApp.xcodeproj -scheme AnglesApp -configuration Debug \
      -destination "id=$udid" -derivedDataPath DerivedDataSimulator build -quiet >&2
  )
  log "installing"
  xcrun simctl install "$udid" "$ROOT/AnglesApp/DerivedDataSimulator/Build/Products/Debug-iphonesimulator/Angles.app"
fi

echo "$udid"
