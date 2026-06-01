#!/usr/bin/env bash
set -euo pipefail

# List issues filtered by a label, emitting Issue[] in contract shape. This is
# the one live call that powers design-epic discovery (list by the epic tag,
# then match body markers client-side). `parent` is always "" here: bulk listing
# does not resolve the sub-issue parent (that would be one GraphQL call per row).
# Usage: issue-list.sh --label <label> [--state all|open|closed] [-g <owner/repo>]
# Depends on: gh, jq.

if ! command -v gh >/dev/null 2>&1; then
  echo "issue-list.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

label=""
state="all"
repo_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) label="${2:-}"; shift 2 ;;
    --state) state="${2:-}"; shift 2 ;;
    -g) repo_override="${2:-}"; shift 2 ;;
    *) echo "issue-list.sh: unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${label}" ]]; then
  echo "issue-list.sh: --label <label> is required" >&2
  exit 1
fi
case "${state}" in
  all|open|closed) ;;
  *) echo "issue-list.sh: --state must be all, open, or closed (got: ${state})" >&2; exit 1 ;;
esac

# the commas belong to gh's --json field list, not array separators
# shellcheck disable=SC2054
args=(issue list --label "${label}" --state "${state}" --limit 200 --json number,title,body,labels,state)
if [[ -n "${repo_override}" ]]; then
  args+=(--repo "${repo_override}")
fi

gh "${args[@]}" | jq '
  map({
    key: (.number | tostring),
    summary: .title,
    description: (.body // ""),
    type: (
      [.labels[].name] |
      if any(. == "type:epic") then "Epic"
      elif any(. == "type:story") then "Story"
      elif any(. == "type:bug") then "Bug"
      elif any(. == "type:task") then "Task"
      else "Task"
      end
    ),
    status: (
      if .state == "CLOSED" then "done"
      else (
        [.labels[].name] as $names |
        if ($names | any(. == "autocode:in-review")) then "in-review"
        elif ($names | any(. == "autocode:in-progress")) then "in-progress"
        elif ($names | any(. == "autocode:todo")) then "todo"
        else "todo"
        end
      )
      end
    ),
    parent: ""
  })
'
