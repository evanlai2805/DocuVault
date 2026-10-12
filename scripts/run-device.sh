#!/usr/bin/env bash
# Build for the connected iPhone, install, and launch. Needs .env.local with DOCUVAULT_TEAM_ID=<10-char team id>.
# Optional: DOCUVAULT_DEVICE=<device name or identifier from `xcrun devicectl list devices`>.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env.local ] && set -a && . ./.env.local && set +a
: "${DOCUVAULT_TEAM_ID:?Set DOCUVAULT_TEAM_ID in .env.local (Xcode → Settings → Accounts → team → Team ID, or developer.apple.com/account → Membership)}"
./scripts/gen.sh >/dev/null
mkdir -p build
set -o pipefail
xcodebuild -project DocuVault.xcodeproj -scheme DocuVault \
  -destination 'generic/platform=iOS' -configuration Debug -skipMacroValidation -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="$DOCUVAULT_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  build 2>&1 | tee build/device.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/device.log || { echo "DEVICE BUILD: FAIL (see build/device.log)"; exit 1; }
APP=build/DerivedData/Build/Products/Debug-iphoneos/DocuVault.app
[ -d "$APP" ] || { echo "App bundle not found at $APP"; exit 1; }

# Pick the device: explicit name/identifier, else the first connected iPhone.
xcrun devicectl list devices --json-output build/devices.json >/dev/null
DEVICE=$(python3 - "$APP" <<'PY'
import json, os, sys
want = os.environ.get("DOCUVAULT_DEVICE", "")
devs = json.load(open("build/devices.json"))["result"]["devices"]
def ok(d):
    hp = d.get("hardwareProperties", {}); cp = d.get("connectionProperties", {})
    return hp.get("deviceType") == "iPhone" and cp.get("pairingState") == "paired"
cands = [d for d in devs if ok(d)]
if want:
    cands = [d for d in cands if want in (d.get("deviceProperties", {}).get("name", ""), d.get("identifier", ""), d.get("hardwareProperties", {}).get("udid", ""))]
if not cands:
    sys.stderr.write("No paired iPhone found. Plug it in, unlock it, trust this Mac, and check Developer Mode.\n"); sys.exit(1)
print(cands[0]["identifier"])
PY
)
echo "Installing on device $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" com.evanlai.docuvault
echo "DEVICE RUN: LAUNCHED"
