#!/usr/bin/env bash
# Compile app + keyboard + MLX for the iOS Simulator. No signing needed. Mirrors .github/workflows/app-build.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/gen.sh >/dev/null
set -o pipefail
xcodebuild -project DocuVault.xcodeproj -scheme DocuVault \
  -destination 'generic/platform=iOS Simulator' -configuration Debug -skipMacroValidation \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  build 2>&1 | tee build/sim.log | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/sim.log && echo "SIM BUILD: PASS" || { echo "SIM BUILD: FAIL (see build/sim.log)"; exit 1; }
