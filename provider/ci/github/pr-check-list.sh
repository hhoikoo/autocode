#!/usr/bin/env bash
set -euo pipefail

# List CI check status for a PR.
# Usage: pr-check-list.sh <pr-number>
# Stdout: JSON array of { name, status, conclusion, link, workflow }.

pr_number="${1:?Usage: pr-check-list.sh <pr-number>}"

gh pr checks "${pr_number}" --json name,status,conclusion,link,workflow
