#!/usr/bin/env bash
# Capture App Store stills on iPhone Duo (outer closed, inner open) at exact Connect sizes.
#
#   demo/make_store_duo.sh [--skip-build] [--outer-only | --inner-only]
#
# Requires iOS 27.1 Simulator runtime and Xcode 27.1. Inner pass waits for the
# inner display (unfold the Duo in Device Hub when prompted).
set -euo pipefail

DEMO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DEMO/.." && pwd)"
STORE="$ROOT/store"
DEVICE_NAME="Angles Store iPhone Duo"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-1"
THEME="$DEMO/themes/lisbon-flight.json"

SKIP_BUILD=0
RUN_OUTER=1
RUN_INNER=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --outer-only) RUN_INNER=0; shift ;;
    --inner-only) RUN_OUTER=0; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

log() { echo "[make_store_duo] $*" >&2; }

open_duo_simulator() {
  local udid="$1"
  local device_hub="/Applications/Xcode.app/Contents/Applications/DeviceHub.app"
  local legacy_sim="/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
  if [[ -d "$device_hub" ]]; then
    log "opening Device Hub (Xcode 27+; there is no standalone Simulator.app)"
    open -a "$device_hub"
  elif [[ -d "$legacy_sim" ]]; then
    open -a "$legacy_sim" --args -CurrentDeviceUDID "$udid"
  else
    log "open Device Hub from Xcode → Open Developer Tool → Device Hub, then pick $DEVICE_NAME"
  fi
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. Install with: $2" >&2; exit 1; }; }

need ffmpeg "brew install ffmpeg"
need node "brew install node"
need python3 "xcode-select --install"
need xcrun "xcode-select --install"
need maestro "curl -fsSL 'https://get.maestro.mobile.dev' | bash"
need pnpm "corepack enable pnpm"

if ! xcrun simctl list runtimes -j | python3 -c "
import json, sys
want = sys.argv[1]
for r in json.load(sys.stdin).get('runtimes', []):
    if r.get('identifier') == want and r.get('isAvailable'):
        sys.exit(0)
sys.exit(1)
" "$RUNTIME"; then
  echo "Missing $RUNTIME. Install iOS 27.1 Simulator: Xcode → Settings → Platforms, or: xcodebuild -downloadPlatform iOS" >&2
  exit 1
fi

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
name, rt = sys.argv[1], sys.argv[2]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if rt not in runtime:
        continue
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"]); sys.exit(0)
' "$DEVICE_NAME" "$RUNTIME" || true)"
if [[ -z "$udid" ]]; then
  log "creating $DEVICE_NAME"
  udid="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")"
fi
log "device $udid"

defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
open_duo_simulator "$udid"
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
  log "building Debug for iPhone Duo (iOS 27.1 SDK)"
  (
    cd "$ROOT/AnglesApp"
    xcodebuild -project AnglesApp.xcodeproj -scheme AnglesApp -configuration Debug \
      -destination "id=$udid" -derivedDataPath DerivedDataSimulatorDuo build -quiet
  )
fi
log "installing"
xcrun simctl install "$udid" "$ROOT/AnglesApp/DerivedDataSimulatorDuo/Build/Products/Debug-iphonesimulator/Angles.app"

token="$(cd "$ROOT/backend" && pnpm --silent demo:session)"

log "screenshot bridge"
node "$DEMO/lib/duo_shot_server.mjs" &
shot_server_pid=$!
cleanup_shot_server() { kill "$shot_server_pid" 2>/dev/null || true; }
trap cleanup_shot_server EXIT
for _ in $(seq 1 50); do
  curl -fsS -m 1 -o /dev/null http://127.0.0.1:8765/health && break
  sleep 0.05
done
curl -fsS -m 1 -o /dev/null http://127.0.0.1:8765/health

harvest_shots() {
  local take="$1"
  python3 - "$take" <<'PY'
from pathlib import Path
import sys
take = Path(sys.argv[1])
shots = take / "shots"
shots.mkdir(exist_ok=True)
for path in take.joinpath("maestro").rglob("*"):
    if not path.is_file():
        continue
    if "/takeScreenshot/" not in str(path).replace("\\", "/"):
        continue
    name = path.name
    if name.endswith(".png.png"):
        dest = shots / name[:-4]
    elif name.endswith(".png"):
        dest = shots / name
    else:
        continue
    if not dest.exists() or dest.stat().st_size < path.stat().st_size:
        dest.write_bytes(path.read_bytes())
print(f"[make_store_duo] harvested {len(list(shots.glob('*.png')))} shots", file=sys.stderr)
PY
}

run_pose() {
  local pose="$1"
  local take="$STORE/raw/duo-${pose}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$take/shots"
  cp "$THEME" "$take/theme.json"
  echo "$pose" >"$take/duo_pose"

  local display_id
  if [[ "$pose" == "inner" ]]; then
    log "Unfold iPhone Duo in Device Hub, then wait for inner display…"
    display_id=""
    for _ in $(seq 1 180); do
      if display_id="$(node -e "
import { enumerateDisplays, displayForPose } from '${DEMO}/lib/duo_display.mjs';
const u = process.argv[1];
try {
  process.stdout.write(displayForPose(enumerateDisplays(u), 'inner'));
} catch { process.exit(1); }
" "$udid" 2>/dev/null)"; then
        break
      fi
      sleep 2
    done
    if [[ -z "$display_id" ]]; then
      echo "Inner display never appeared. Unfold the Duo simulator and re-run with --inner-only." >&2
      exit 1
    fi
  else
    display_id="$(node -e "
import { enumerateDisplays, displayForPose } from '${DEMO}/lib/duo_display.mjs';
process.stdout.write(displayForPose(enumerateDisplays(process.argv[1]), 'outer'));
" "$udid")"
  fi
  log "$pose display $display_id → $take"

  log "launching entitled demo ($pose)"
  xcrun simctl launch --terminate-running-process "$udid" app.angles.ios \
    -AnglesDemoSessionToken "$token" -AnglesDemoEntitled YES >/dev/null
  maestro --device "$udid" test "$DEMO/flows/warmup.yaml"

  local flow_status=0
  maestro --device "$udid" test --debug-output "$take/maestro" \
    -e DEMO_LINE="$DEMO_LINE" -e FOLLOWUP_REPLY="$FOLLOWUP_REPLY" -e BEST_STYLE="$BEST_STYLE" \
    -e SHOT_DIR="$take/shots" -e DUO_UDID="$udid" -e DUO_DISPLAY_ID="$display_id" \
    "$DEMO/store_flow_duo.yaml" >"$take/maestro.txt" 2>&1 || flow_status=$?

  harvest_shots "$take"

  if [[ "$flow_status" != 0 ]]; then
    echo "Duo store flow failed ($pose). See $take/maestro.txt" >&2
    rg -n 'FAILED|Assertion|Unable|error' "$take/maestro.txt" | tail -30 >&2 || true
    exit 1
  fi

  node "$DEMO/lib/extract_result.mjs" "$take"
  node "$DEMO/store_edit.mjs" "$take" --duo "$pose"
  log "composed store/duo/$pose"
}

if [[ "$RUN_OUTER" == 1 ]]; then
  run_pose outer
fi
if [[ "$RUN_INNER" == 1 ]]; then
  run_pose inner
fi

log "done — store/duo/outer and store/duo/inner (upload with node demo/store_upload_duo.mjs when version 1.0 is editable)"
