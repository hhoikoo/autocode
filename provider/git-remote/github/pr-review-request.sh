#!/usr/bin/env bash
set -euo pipefail

# Request PR review from one or more reviewers.
# Tolerates reviewers already on the PR.
# Usage: pr-review-request.sh <pr-number> <reviewer> [<reviewer>...]

pr_number="${1:?Usage: pr-review-request.sh <pr-number> <reviewer> [<reviewer>...]}"
shift

if [[ $# -eq 0 ]]; then
  echo "pr-review-request.sh: at least one reviewer required" >&2
  exit 1
fi

failed=0
for reviewer in "$@"; do
  # One mutation per reviewer; capture stderr so an "already requested" error is
  # tolerated without re-running (a re-run can flip a real failure to success).
  if ! err=$(gh pr edit "${pr_number}" --add-reviewer "${reviewer}" 2>&1); then
    if echo "${err}" | grep -qiE 'already (a )?(requested|reviewer)|already has a review|cannot request review from'; then
      echo "pr-review-request.sh: ${reviewer} already on PR #${pr_number}, skipping" >&2
      continue
    fi
    echo "pr-review-request.sh: failed to add ${reviewer}: ${err}" >&2
    failed=1
  fi
done

exit "${failed}"
