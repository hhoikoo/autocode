#!/usr/bin/env bash
set -euo pipefail

# Ensure a label exists in the repo, creating or updating it. Idempotent.
# Needed before creating issues with a dynamic label (e.g. an epic tag): GitHub
# rejects `issue create --label X` when X does not yet exist.
# Usage: issue-label-ensure.sh <name> [--color <hex>] [--description <text>] [-g <owner/repo>]
# Depends on: gh.

if ! command -v gh >/dev/null 2>&1; then
  echo "issue-label-ensure.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

name=""
color=""
description=""
repo_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --color) color="${2:-}"; shift 2 ;;
    --description) description="${2:-}"; shift 2 ;;
    -g) repo_override="${2:-}"; shift 2 ;;
    -*) echo "issue-label-ensure.sh: unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -z "${name}" ]]; then
        name="$1"; shift
      else
        echo "issue-label-ensure.sh: unexpected argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${name}" ]]; then
  echo "issue-label-ensure.sh: <name> is required" >&2
  exit 1
fi

args=(label create "${name}" --force)
if [[ -n "${color}" ]]; then args+=(--color "${color}"); fi
if [[ -n "${description}" ]]; then args+=(--description "${description}"); fi
if [[ -n "${repo_override}" ]]; then args+=(--repo "${repo_override}"); fi

gh "${args[@]}" >/dev/null
