#!/usr/bin/env bash
set -euo pipefail

# Return the current GitHub user as JSON {login, id}.
# Usage: current-user.sh
# Depends on: gh, jq.

if ! command -v gh >/dev/null 2>&1; then
  echo "current-user.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

gh api user | jq '{login: .login, id: (.id | tostring)}'
