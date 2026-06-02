#!/usr/bin/env bash
set -euo pipefail

# Create a pull request.
# Usage: pr-create.sh --title <t> --body-file <p> [--base <b>] [--assignee <a>] [--no-review]
# Stdout: created PR URL on a single line.

title=""
body_file=""
base=""
assignee=""
no_review=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      title="${2:?--title requires a value}"
      shift 2
      ;;
    --body-file)
      body_file="${2:?--body-file requires a value}"
      shift 2
      ;;
    --base)
      base="${2:?--base requires a value}"
      shift 2
      ;;
    --assignee)
      assignee="${2:?--assignee requires a value}"
      shift 2
      ;;
    --no-review)
      no_review=1
      shift
      ;;
    *)
      echo "pr-create.sh: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${title}" ]]; then
  echo "pr-create.sh: --title is required" >&2
  exit 1
fi
if [[ -z "${body_file}" ]]; then
  echo "pr-create.sh: --body-file is required" >&2
  exit 1
fi
if [[ ! -f "${body_file}" ]]; then
  echo "pr-create.sh: body file not found: ${body_file}" >&2
  exit 1
fi

args=(pr create --title "${title}" --body-file "${body_file}")
if [[ -n "${base}" ]]; then
  args+=(--base "${base}")
fi
if [[ -n "${assignee}" ]]; then
  args+=(--assignee "${assignee}")
fi
if [[ "${no_review}" -eq 1 ]]; then
  # gh requests reviewers only when --reviewer is passed, so omitting it is how
  # a PR opens without requesting reviews. Passing --reviewer "" instead sends
  # an empty handle that gh rejects. Server-side CODEOWNERS auto-request, when
  # the repo enables it, is not controllable from gh.
  :
fi

gh "${args[@]}"
