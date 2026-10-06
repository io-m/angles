#!/usr/bin/env bash
# One command: real cook on the demo Simulator, recorded, then edited to
# demo/output/final_9x16.mp4. Cut contract: demo/README.md (hook, type, short
# cook, four chapters, Tough love hold, outro). Do not add Post or Home.
#
#   demo/make_video.sh                         # full run (build, record, edit, check)
#   demo/make_video.sh --theme lisbon-flight   # demo/themes/lisbon-flight.json
#   demo/make_video.sh --skip-build            # reuse the installed Simulator build
#   demo/make_video.sh --reuse-take demo/raw/take-20261002-210000   # re-edit only
#
# Env overrides (win over the theme): DEMO_LINE, FOLLOWUP_REPLY, BEST_STYLE
# BEST_STYLE affects report.md scoring only, not the picture.
set -euo pipefail

DEMO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DEMO/.." && pwd)"

TAKE=""
THEME=""
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reuse-take) TAKE="$(cd "$2" && pwd)"; shift 2 ;;
    --theme) THEME="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$THEME" && "$THEME" != */* && "$THEME" != *.json ]]; then
  THEME="$DEMO/themes/$THEME.json"
fi
if [[ -z "$THEME" ]]; then
  if [[ -n "$TAKE" && -f "$TAKE/theme.json" ]]; then
    THEME="$TAKE/theme.json"
  else
    THEME="$DEMO/themes/lost-job.json"
  fi
fi
[[ -f "$THEME" ]] || { echo "No theme at $THEME" >&2; exit 1; }
THEME="$(cd "$(dirname "$THEME")" && pwd)/$(basename "$THEME")"
theme_field() { node -e 'const t = require(process.argv[1]); process.stdout.write(String(t[process.argv[2]] ?? ""))' "$THEME" "$1"; }
DEMO_LINE="${DEMO_LINE:-$(theme_field line)}"
FOLLOWUP_REPLY="${FOLLOWUP_REPLY:-$(theme_field followupReply)}"
BEST_STYLE="${BEST_STYLE:-$(theme_field bestStyle)}"
BEST_STYLE="${BEST_STYLE:-auto}"
[[ -n "$DEMO_LINE" ]] || { echo "$THEME has no \"line\"" >&2; exit 1; }

log() { echo "[make_video] $*" >&2; }
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. Install with: $2" >&2; exit 1; }
}
now_ms() { node -e 'process.stdout.write(String(Date.now()))'; }

need ffmpeg "brew install ffmpeg"
need ffprobe "brew install ffmpeg"
need node "brew install node"
need npx "brew install node"

record_take() {
  need maestro "curl -fsSL 'https://get.maestro.mobile.dev' | bash"
  need java "brew install openjdk@17"
  need pnpm "corepack enable pnpm"
  need xcrun "xcode-select --install"
  need rg "brew install ripgrep"

  local api
  api="$(rg -o 'ANGLES_API_BASE_URL: "([^"]+)"' -r '$1' "$ROOT/AnglesApp/project.yml" | head -1)"
  if ! curl -fsS -m 5 "$api/health" | rg -q '"db":"ok"'; then
    echo "The local API at $api is not healthy. Start it with: (cd backend && pnpm dev)" >&2
    exit 1
  fi
  local api_host lan_ip
  api_host="$(node -e 'process.stdout.write(new URL(process.argv[1]).hostname)' "$api")"
  lan_ip="$(ipconfig getifaddr en0 || true)"
  if [[ "$api_host" != "localhost" && "$api_host" != "127.0.0.1" && "$api_host" != "$lan_ip" ]]; then
    echo "Debug ANGLES_API_BASE_URL points at $api_host but this Mac is $lan_ip. Update project.yml." >&2
    exit 1
  fi

  local udid token
  if [[ "$SKIP_BUILD" == 1 ]]; then
    udid="$("$DEMO/setup_sim.sh" --no-build | tail -1)"
  else
    udid="$("$DEMO/setup_sim.sh" | tail -1)"
  fi
  token="$(cd "$ROOT/backend" && pnpm --silent demo:session)"

  log "launching on $udid"
  xcrun simctl launch --terminate-running-process "$udid" app.angles.ios \
    -AnglesDemoSessionToken "$token" -AnglesDemoEntitled YES >/dev/null
  maestro --device "$udid" test "$DEMO/flows/warmup.yaml" >&2

  TAKE="$DEMO/raw/take-$(date +%Y%m%d-%H%M%S)"
  if [[ -e "$TAKE" ]]; then
    echo "$TAKE already exists; refusing to overwrite a take." >&2
    exit 1
  fi
  mkdir -p "$TAKE"
  cp "$THEME" "$TAKE/theme.json"
  log "recording into $TAKE"

  xcrun simctl io "$udid" recordVideo --codec=h264 "$TAKE/screen.mp4" 2>"$TAKE/record.log" &
  local rec_pid=$!
  for _ in $(seq 1 200); do
    rg -q 'Recording started' "$TAKE/record.log" 2>/dev/null && break
    sleep 0.05
  done
  now_ms >"$TAKE/record_start_ms"
  sleep 1

  local flow_status=0
  maestro --device "$udid" test --debug-output "$TAKE/maestro" \
    -e DEMO_LINE="$DEMO_LINE" -e FOLLOWUP_REPLY="$FOLLOWUP_REPLY" -e BEST_STYLE="$BEST_STYLE" \
    "$DEMO/demo_flow.yaml" >"$TAKE/maestro.txt" 2>&1 || flow_status=$?
  maestro --device "$udid" hierarchy >"$TAKE/hierarchy.raw" 2>/dev/null || true

  kill -INT "$rec_pid"
  wait "$rec_pid" || true

  node "$DEMO/lib/extract_result.mjs" "$TAKE"
  if [[ "$flow_status" != 0 ]]; then
    echo "The flow stopped early. See $TAKE/maestro.txt:" >&2
    rg -n 'FAILED|Assertion is false|label' "$TAKE/maestro.txt" | tail -5 >&2 || true
    exit 1
  fi
}

if [[ -z "$TAKE" ]]; then
  record_take
fi
node "$DEMO/edit.mjs" "$TAKE" "$THEME"
node "$DEMO/check.mjs" "$TAKE"

KEEP="$DEMO/output/$(basename "$THEME" .json)_$(basename "$TAKE").mp4"
if [[ "$(basename "$THEME")" == theme.json ]]; then
  KEEP="$DEMO/output/$(basename "$TAKE").mp4"
fi
cp "$DEMO/output/final_9x16.mp4" "$KEEP"
log "kept a copy at ${KEEP#"$ROOT/"}"
