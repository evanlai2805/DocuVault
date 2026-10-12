#!/usr/bin/env bash
# Regenerate DocuVault.xcodeproj from project.yml. Run after git pull or any project.yml change.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
xcodegen generate
