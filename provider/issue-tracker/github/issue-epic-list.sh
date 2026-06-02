#!/usr/bin/env bash
set -euo pipefail

# List a design epic's issues (the epic plus its unit sub-issues) in contract
# Issue[] shape. This is the one live call that powers design-epic discovery.
# Usage: issue-epic-list.sh --epic <id> [-g <owner/repo>]
# Depends on: gh, jq.
#
# GitHub uses no per-epic label: the epic is found by its `<!-- autocode:epic=<id> -->`
# body marker, and its units come from the native sub-issues relationship. HTML
# comment markers are not search-indexed, so the epic lookup is a strongly
# consistent scan of repo issues (state=all, so a closed/archived epic is found);
# units are then read from the epic's sub-issues. A flat design is its own epic
# with zero sub-issues. Emits [] when no issue carries the epic marker (not yet
# fanned out).

if ! command -v gh >/dev/null 2>&1; then
  echo "issue-epic-list.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

id=""
repo_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic) id="${2:-}"; shift 2 ;;
    -g) repo_override="${2:-}"; shift 2 ;;
    *) echo "issue-epic-list.sh: unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${id}" ]]; then
  echo "issue-epic-list.sh: --epic <id> is required" >&2
  exit 1
fi

if [[ -n "${repo_override}" ]]; then
  owner="${repo_override%%/*}"
  name="${repo_override##*/}"
else
  repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
  owner="${repo%%/*}"
  name="${repo##*/}"
fi

epic_marker="<!-- autocode:epic=${id} -->"

# An issue REST object (epic from the scan, units from sub_issues) -> contract Issue.
# `$parent` is the epic key for units, "" for the epic itself.
# jq program text, not a shell expansion
# shellcheck disable=SC2016
issue_filter='
  def to_issue($parent):
    {
      key: (.number | tostring),
      summary: .title,
      description: (.body // ""),
      type: (
        if (.type and .type.name) then .type.name
        else (
          [.labels[].name] |
          if any(. == "type:epic") then "Epic"
          elif any(. == "type:story") then "Story"
          elif any(. == "type:bug") then "Bug"
          elif any(. == "type:task") then "Task"
          else "Task"
          end
        )
        end
      ),
      status: (
        if .state == "closed" then "done"
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
      parent: $parent
    };
'

# Find the epic: first issue (not a PR) whose body carries the epic marker.
epic=$(gh api --paginate "/repos/${owner}/${name}/issues?state=all&per_page=100" \
  | jq -c --arg m "${epic_marker}" '
      [ .[] | select(.pull_request | not) | select(.body != null and (.body | contains($m))) ][0]
    ' \
  | jq -s 'map(select(. != null))[0] // empty')

if [[ -z "${epic}" ]]; then
  printf '[]\n'
  exit 0
fi

epic_number=$(printf '%s' "${epic}" | jq -r '.number')

# Units: the epic's native sub-issues (empty for a flat design).
units=$(gh api --paginate "/repos/${owner}/${name}/issues/${epic_number}/sub_issues" \
  | jq -s 'add // []')

printf '%s' "${epic}" | jq \
  --argjson units "${units}" \
  --arg epickey "${epic_number}" \
  "${issue_filter}"'
    [ to_issue("") ] + ($units | map(to_issue($epickey)))
  '
