#!/usr/bin/env bash
set -euo pipefail

# List recent CI workflow runs for a branch.
# Usage: run-list.sh --branch <b> [--limit <N>]   (default limit: 10)
# Stdout: JSON array of
#   { databaseId, headBranch, status, conclusion, workflowName, createdAt, url }.

branch=""
limit=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      branch="${2:?--branch requires a value}"
      shift 2
      ;;
    --limit)
      limit="${2:?--limit requires a value}"
      shift 2
      ;;
    *)
      echo "run-list.sh: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${branch}" ]]; then
  echo "run-list.sh: --branch is required" >&2
  exit 1
fi

gh run list \
  --branch "${branch}" \
  --limit "${limit}" \
  --json databaseId,headBranch,status,conclusion,workflowName,createdAt,url
