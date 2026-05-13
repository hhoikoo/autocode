#!/usr/bin/env bash
set -euo pipefail

# Ensure a PR body contains "Closes #<issue-id>". Idempotent.
# Usage: pr-issue-link.sh <pr-number> <issue-id>

pr_number="${1:?Usage: pr-issue-link.sh <pr-number> <issue-id>}"
issue_id="${2:?Usage: pr-issue-link.sh <pr-number> <issue-id>}"

body=$(gh pr view "${pr_number}" --json body -q .body)

# Idempotency: skip if any GitHub auto-close keyword already references the
# issue. GitHub recognizes close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved.
pattern='(^|[^[:alnum:]])([Cc]los(e|es|ed)|[Ff]ix(es|ed)?|[Rr]esolv(e|es|ed))[[:space:]]+#'"${issue_id}"'([^0-9]|$)'
if printf '%s' "${body}" | grep -Eq "${pattern}"; then
  echo "pr-issue-link.sh: PR #${pr_number} already references issue #${issue_id}" >&2
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
printf '%s\n\nCloses #%s\n' "${body}" "${issue_id}" > "${tmp}"
gh pr edit "${pr_number}" --body-file "${tmp}"
