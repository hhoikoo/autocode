#!/usr/bin/env bash
set -euo pipefail

# Merge a PR.
# Usage: pr-merge.sh <pr-number> [--admin] [--squash|--merge|--rebase]
# Default merge method is --squash. --admin bypasses required reviews/checks.
# Side-effect only; no stdout. Idempotent: an already-merged PR is a no-op.

pr_number="${1:?Usage: pr-merge.sh <pr-number> [--admin] [--squash|--merge|--rebase]}"
shift

method="--squash"
admin=""
for arg in "$@"; do
  case "${arg}" in
    --admin) admin="--admin" ;;
    --squash | --merge | --rebase) method="${arg}" ;;
    *)
      echo "pr-merge.sh: unknown argument: ${arg}" >&2
      exit 1
      ;;
  esac
done

state="$(gh pr view "${pr_number}" --json state -q .state)"
if [[ "${state}" == "MERGED" ]]; then
  echo "pr-merge.sh: PR #${pr_number} already merged" >&2
  exit 0
fi

# shellcheck disable=SC2086
# admin is intentionally unquoted: empty means omit the flag entirely.
gh pr merge "${pr_number}" ${admin} "${method}"
