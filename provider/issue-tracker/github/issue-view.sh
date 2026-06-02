#!/usr/bin/env bash
set -euo pipefail

# View a GitHub issue and emit the issue-tracker contract JSON.
# Usage: issue-view.sh <key>
# Depends on: gh, jq.
#
# Reads the issue over REST so the native Issue Type (`.type.name`) is available;
# `type` reports it when set, else falls back to the `type:<x>` label.

if ! command -v gh >/dev/null 2>&1; then
  echo "issue-view.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: issue-view.sh <key>" >&2
  exit 1
fi

issue_number="$1"

repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
owner="${repo%%/*}"
name="${repo##*/}"

# Resolve parent via the sub-issues GraphQL API. Suppress failure; emit empty.
# shellcheck disable=SC2016
parent_number=$(gh api graphql \
  -H "GraphQL-Features:sub_issues" \
  -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issue(number: $number) {
          parent { number }
        }
      }
    }
  ' \
  -f owner="${owner}" \
  -f name="${name}" \
  -F number="${issue_number}" \
  --jq '.data.repository.issue.parent.number // empty' 2>/dev/null || echo "")

gh api "/repos/${owner}/${name}/issues/${issue_number}" \
  | jq --arg parent "${parent_number}" '
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
          else "todo"
          end
        )
        end
      ),
      parent: $parent
    }
  '
