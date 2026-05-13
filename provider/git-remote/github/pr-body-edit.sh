#!/usr/bin/env bash
set -euo pipefail

# Replace a PR's body text.
# Usage: pr-body-edit.sh <pr-number> <body-file-path>

pr_number="${1:?Usage: pr-body-edit.sh <pr-number> <body-file-path>}"
body_file="${2:?Usage: pr-body-edit.sh <pr-number> <body-file-path>}"

if [[ ! -f "${body_file}" ]]; then
  echo "pr-body-edit.sh: body file not found: ${body_file}" >&2
  exit 1
fi

gh pr edit "${pr_number}" --body-file "${body_file}"
