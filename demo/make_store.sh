#!/usr/bin/env bash
# Capture App Store stills and a screen recording on the 6.9" simulator.
#
#   demo/make_store.sh
#   demo/make_store.sh --skip-build
#   demo/make_store.sh --reuse-take store/raw/take-…
#
# Writes store/raw/take-… and then demo/store_edit.mjs composes store/*.png and store/preview.mp4.
set -euo pipefail

DEMO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DEMO/.." && pwd)"
STORE="$ROOT/store"
DEVICE_NAME="Angles Store iPhone 17 Pro Max"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
THEME="$DEMO/themes/lisbon-flight.json"

TAKE=""
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reuse-take) TAKE="$(cd "$2" && pwd)"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

log() { echo "[make_store] $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. Install with: $2" >&2; exit 1; }; }
now_ms() { node -e 'process.stdout.write(String(Date.now()))'; }

need ffmpeg "brew install ffmpeg"
need node "brew install node"
need python3 "xcode-select --install"
need xcrun "xcode-select --install"

if [[ -n "$TAKE" ]]; then
  node "$DEMO/store_edit.mjs" "$TAKE"
  exit 0
fi

need maestro "curl -fsSL 'https://get.maestro.mobile.dev' | bash"
need pnpm "corepack enable pnpm"

api="$(rg -o 'ANGLES_API_BASE_URL: "([^"]+)"' -r '$1' "$ROOT/AnglesApp/project.yml" | head -1)"
if ! curl -fsS -m 5 "$api/health" | rg -q '"db":"ok"'; then
  echo "The local API at $api is not healthy. Start it with: (cd backend && pnpm dev)" >&2
  exit 1
fi

DEMO_LINE="$(node -e 'process.stdout.write(require(process.argv[1]).line)' "$THEME")"
FOLLOWUP_REPLY="$(node -e 'process.stdout.write(require(process.argv[1]).followupReply)' "$THEME")"
BEST_STYLE="$(node -e 'process.stdout.write(String(require(process.argv[1]).bestStyle || "auto"))' "$THEME")"

udid="$(xcrun simctl list devices -j | python3 -c '
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

defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
state="$(xcrun simctl list devices | rg -F "$udid" | rg -o '\((Booted|Shutdown)\)' || true)"
if [[ "$state" != "(Booted)" ]]; then
  log "booting"
  xcrun simctl boot "$udid"
fi
xcrun simctl bootstatus "$udid" -b >/dev/null

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
for key in KeyboardAutocorrection KeyboardPrediction KeyboardShowPredictionBar \
  KeyboardCheckSpelling KeyboardSmartPunctuation; do
  xcrun simctl spawn "$udid" defaults write com.apple.Preferences "$key" -bool NO
done
for key in DidShowContinuousPathIntroduction DidShowGestureKeyboardIntroduction \
  KeyboardDidShowProductivityTutorial; do
  xcrun simctl spawn "$udid" defaults write com.apple.Preferences "$key" -bool YES
done

if [[ "$SKIP_BUILD" == 0 ]]; then
  log "building Debug for the Store simulator"
  (
    cd "$ROOT/AnglesApp"
    xcodebuild -project AnglesApp.xcodeproj -scheme AnglesApp -configuration Debug \
      -destination "id=$udid" -derivedDataPath DerivedDataSimulator build -quiet
  )
fi
log "installing"
xcrun simctl install "$udid" "$ROOT/AnglesApp/DerivedDataSimulator/Build/Products/Debug-iphonesimulator/Angles.app"

token="$(cd "$ROOT/backend" && pnpm --silent demo:session)"
log "launching entitled demo"
xcrun simctl launch --terminate-running-process "$udid" app.angles.ios \
  -AnglesDemoSessionToken "$token" -AnglesDemoEntitled YES >/dev/null
maestro --device "$udid" test "$DEMO/flows/warmup.yaml"

TAKE="$STORE/raw/take-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TAKE/shots"
cp "$THEME" "$TAKE/theme.json"
log "recording into $TAKE"

xcrun simctl io "$udid" recordVideo --codec=h264 --mask=ignored "$TAKE/screen.mp4" 2>"$TAKE/record.log" &
rec_pid=$!
for _ in $(seq 1 200); do
  rg -q 'Recording started' "$TAKE/record.log" 2>/dev/null && break
  sleep 0.05
done
now_ms >"$TAKE/record_start_ms"
sleep 0.4

flow_status=0
maestro --device "$udid" test --debug-output "$TAKE/maestro" \
  -e DEMO_LINE="$DEMO_LINE" -e FOLLOWUP_REPLY="$FOLLOWUP_REPLY" -e BEST_STYLE="$BEST_STYLE" \
  -e SHOT_DIR="$TAKE/shots" \
  "$DEMO/store_flow.yaml" >"$TAKE/maestro.txt" 2>&1 || flow_status=$?

# Let the last style (Tough love hold) and shown_tough_love land before we stop.
sleep 6.0
kill -INT "$rec_pid" 2>/dev/null || true
wait "$rec_pid" 2>/dev/null || true

if [[ "$flow_status" != 0 ]]; then
  echo "Store flow failed. See $TAKE/maestro.txt" >&2
  rg -n 'FAILED|Assertion|Unable|error' "$TAKE/maestro.txt" | tail -30 >&2 || true
  exit 1
fi

node "$DEMO/lib/extract_result.mjs" "$TAKE"

# Maestro --debug-output often keeps takeScreenshot copies under the debug tree
# instead of writing the destination path. Harvest those into $TAKE/shots.
python3 - "$TAKE" <<'PY'
from pathlib import Path
import sys
take = Path(sys.argv[1])
shots = take / "shots"
shots.mkdir(exist_ok=True)
for path in take.joinpath("maestro").rglob("*"):
    if not path.is_file():
        continue
    name = path.name
    if "/takeScreenshot/" not in str(path).replace("\\", "/"):
        continue
    if name.endswith(".png.png"):
        dest = shots / name[:-4]
    elif name.endswith(".png"):
        dest = shots / name
    else:
        continue
    if not dest.exists() or dest.stat().st_size < path.stat().st_size:
        dest.write_bytes(path.read_bytes())
print(f"[make_store] harvested {len(list(shots.glob('*.png')))} shots", file=sys.stderr)
PY

if [[ -f "$STORE/paywall.png" ]]; then
  log "keeping existing paywall.png for subscription review shots"
else
  log "paywall, without the demo entitlement"
  xcrun simctl terminate "$udid" app.angles.ios >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" app.angles.ios \
    -AnglesDemoSessionToken "$token" -AnglesDemoEntitled NO >/dev/null
  if maestro --device "$udid" test --debug-output "$TAKE/paywall-maestro" \
    -e SHOT_DIR="$TAKE/shots" \
    "$DEMO/store_paywall.yaml" >"$TAKE/paywall.txt" 2>&1; then
    log "paywall screenshot saved"
  else
    log "simulator paywall had no prices (see $TAKE/paywall.txt)"
  fi
fi

node "$DEMO/store_edit.mjs" "$TAKE"
log "take $TAKE"
