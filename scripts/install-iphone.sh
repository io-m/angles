#!/usr/bin/env bash
# Build Angles and install it on a connected iPhone.
#
# Usage:
#   ./scripts/install-iphone.sh
#   DEVICE="Joe’s iPhone" ./scripts/install-iphone.sh
#
# If ~/Documents/Angles.icon exists, it is copied into the app first
# (so Icon Composer edits land in the next build).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/AnglesApp"
ICON_SRC="${ICON_SRC:-$HOME/Documents/Angles.icon}"
ICON_DST="$APP_DIR/AnglesApp/Angles.icon"
DERIVED="$APP_DIR/DerivedData"
BUNDLE_ID="app.angles.ios"

copy_icon_from_documents() {
  local tmp
  tmp="$(mktemp -d)"
  if cp -R "$ICON_SRC" "$tmp/Angles.icon" 2>/dev/null; then
    rm -rf "$ICON_DST"
    mv "$tmp/Angles.icon" "$ICON_DST"
    rm -rf "$tmp"
    echo "Copied icon from $ICON_SRC"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

if [[ -d "$ICON_SRC" ]]; then
  if ! copy_icon_from_documents; then
    echo "This terminal cannot read $ICON_SRC (macOS Documents permission)."
    echo "Building with the icon already in the project: $ICON_DST"
  fi
else
  echo "No $ICON_SRC — using $ICON_DST"
fi

if [[ ! -d "$ICON_DST" ]]; then
  echo "No app icon at $ICON_DST" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

(
  cd "$APP_DIR"
  xcodegen generate
)

destination_id="${DEVICE_ID:-}"
if [[ -z "$destination_id" ]]; then
  wanted="${DEVICE:-Joe’s iPhone}"
  destinations="$(xcodebuild -project "$APP_DIR/AnglesApp.xcodeproj" -scheme AnglesApp -showdestinations 2>/dev/null || true)"
  destination_id="$(
    WANTED="$wanted" python3 -c '
import os, re, sys
wanted = os.environ["WANTED"]
text = sys.stdin.read()
pattern = re.compile(r"\{ platform:iOS, arch:arm64, id:([^,]+), name:(.+) \}")
matches = pattern.findall(text)
if not matches:
    sys.exit(0)
for udid, name in matches:
    if name.strip() == wanted:
        print(udid.strip())
        sys.exit(0)
print(matches[0][0].strip())
' <<<"$destinations"
  )"
fi

if [[ -z "$destination_id" ]]; then
  echo "No physical iPhone found. Connect one and unlock it." >&2
  xcodebuild -project "$APP_DIR/AnglesApp.xcodeproj" -scheme AnglesApp -showdestinations
  exit 1
fi

echo "Building for device $destination_id"
xcodebuild \
  -project "$APP_DIR/AnglesApp.xcodeproj" \
  -scheme AnglesApp \
  -destination "platform=iOS,id=$destination_id" \
  -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM=36U79UTZM9 \
  CODE_SIGN_STYLE=Automatic \
  build

APP="$DERIVED/Build/Products/Debug-iphoneos/Angles.app"
if [[ ! -d "$APP" ]]; then
  echo "Build succeeded but $APP is missing." >&2
  exit 1
fi

echo "Installing $APP"
xcrun devicectl device install app --device "$destination_id" "$APP"
echo "Launching $BUNDLE_ID"
xcrun devicectl device process launch --terminate-existing --device "$destination_id" "$BUNDLE_ID"
echo "Done. Look for Angles on the Home Screen."
