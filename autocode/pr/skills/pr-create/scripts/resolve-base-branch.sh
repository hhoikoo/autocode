#!/usr/bin/env bash
set -euo pipefail

# Resolve the base branch for the current repo.
# Stdout: resolved base branch name (plain text, single line).
# Stderr: brief progress.
# Exit: 0 on success, 1 on failure.

base=""

if command -v gh >/dev/null 2>&1; then
  base="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
fi

if [[ -z "${base}" ]]; then
  ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "${ref}" ]]; then
    base="${ref#refs/remotes/origin/}"
  fi
fi

if [[ -z "${base}" ]]; then
  echo "resolve-base-branch: could not resolve default branch" >&2
  exit 1
fi

echo "resolved base: ${base}" >&2
echo "${base}"
