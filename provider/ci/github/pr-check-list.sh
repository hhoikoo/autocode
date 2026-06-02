#!/usr/bin/env bash
set -euo pipefail

# List CI check status for a PR.
# Usage: pr-check-list.sh <pr-number>
# Stdout: JSON array of { name, bucket, state, link, workflow }.

pr_number="${1:?Usage: pr-check-list.sh <pr-number>}"

# `gh pr checks` exits non-zero when checks are failing (1) or pending (8), and
# emits "no checks reported" with empty stdout when none exist. The JSON still
# lands on stdout in the failing/pending cases, so tolerate the exit code and
# treat empty output as the no-checks case.
checks=$(gh pr checks "${pr_number}" --json name,bucket,state,link,workflow 2>/dev/null) || true

if [[ -z "${checks}" ]]; then
  printf '[]\n'
else
  printf '%s\n' "${checks}"
fi
