#!/usr/bin/env bash
set -euo pipefail

# Show the failed log output for a CI run, capped at the last 200 lines.
# Usage: run-view-failed.sh <run-id>

run_id="${1:?Usage: run-view-failed.sh <run-id>}"

gh run view "${run_id}" --log-failed | tail -n 200
