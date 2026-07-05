#!/usr/bin/env bash
set -euo pipefail

# Convert an already-opened PR to draft (wraps `gh pr ready <pr> --undo`).
# Usage: pr-draft.sh <pr> [-g <owner/repo>]
# Side-effect only, no stdout. Idempotent: an already-draft PR is a no-op (exit 0).
# Depends on: gh.

if ! command -v gh >/dev/null 2>&1; then
  echo "pr-draft.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

pr_number=""
repo_override=""
repo_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g) repo_override="${2:?Usage: pr-draft.sh <pr> [-g <owner/repo>]}"; shift 2 ;;
    -*)
      echo "pr-draft.sh: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "${pr_number}" ]]; then
        pr_number="$1"
      else
        echo "pr-draft.sh: unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

: "${pr_number:?Usage: pr-draft.sh <pr> [-g <owner/repo>]}"

if [[ -n "${repo_override}" ]]; then
  repo_args=(--repo "${repo_override}")
fi

# `gh pr ready <pr> --undo` converts open -> draft. An already-draft PR makes gh
# exit non-zero with an "already a draft" message; swallow that one case so the
# script stays idempotent, and re-raise any other failure.
err=$(gh pr ready "${pr_number}" ${repo_args[@]+"${repo_args[@]}"} --undo 2>&1) || {
  if printf '%s' "${err}" | grep -qi 'draft'; then
    exit 0
  fi
  printf '%s\n' "${err}" >&2
  exit 1
}
