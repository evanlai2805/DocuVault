#!/usr/bin/env bash
# Regenerate DocuVault.xcodeproj from project.yml. Run after git pull or any project.yml change.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
# Signing team comes from .env.local (git-ignored), so a regenerated project never loses it and ⌘R
# just works. CI has no .env.local and signs nothing, so the team stays empty there.
[ -f .env.local ] && set -a && . ./.env.local && set +a
export DOCUVAULT_TEAM_ID="${DOCUVAULT_TEAM_ID:-}"
xcodegen generate
