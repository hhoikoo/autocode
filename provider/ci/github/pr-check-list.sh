#!/usr/bin/env bash
set -euo pipefail

# List CI check status for a PR.
# Usage: pr-check-list.sh <pr-number>
# Stdout: JSON array of { name, bucket, state, link, workflow }.

pr_number="${1:?Usage: pr-check-list.sh <pr-number>}"

# `gh pr checks` exits 0 (all pass), 1 (a check failing), or 8 (checks pending);
# the JSON lands on stdout in all three, empty only in the genuine no-checks case
# (which prints "no checks reported" on stderr). Any other exit code is a real
# failure (auth, network, unknown PR): surface it and exit 2, never mask it as an
# empty "[]" that a caller reads as CI green.
rc=0
err_file="$(mktemp)"
trap 'rm -f "${err_file}"' EXIT
checks=$(gh pr checks "${pr_number}" --json name,bucket,state,link,workflow 2>"${err_file}") || rc=$?
err="$(cat "${err_file}")"

case "${rc}" in
  0 | 1 | 8) ;;
  *)
    echo "pr-check-list: gh pr checks failed (rc=${rc}): ${err}" >&2
    exit 2
    ;;
esac

if [[ -z "${checks}" ]]; then
  # Empty stdout is legitimate only for the genuine no-checks case.
  if [[ "${err}" == *"no checks reported"* ]]; then
    printf '[]\n'
  else
    echo "pr-check-list: gh pr checks returned no output (rc=${rc}): ${err}" >&2
    exit 2
  fi
else
  printf '%s\n' "${checks}"
fi
