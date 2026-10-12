#!/usr/bin/env bash
# Show the GitHub Actions result for the latest commits and the annotations of the newest run.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gh >/dev/null || { echo "gh missing: brew install gh && gh auth login"; exit 1; }
gh run list --limit 4 --json name,status,conclusion,headSha,databaseId \
  --jq '.[] | "\(.databaseId)  \(.headSha[0:7])  \(.status)  \(.conclusion // "-")  \(.name)"'
RUN=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
JOB=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN/jobs" --jq '.jobs[0].id')
gh api "repos/{owner}/{repo}/check-runs/$JOB/annotations" --jq '.[] | "\(.annotation_level): \(.title // "") \(.message)"' | grep -v "Node.js" | head -30
