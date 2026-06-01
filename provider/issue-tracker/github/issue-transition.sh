#!/usr/bin/env bash
set -euo pipefail

# Move an issue to one of the four contract states. Open states are distinguished
# by an autocode:<state> label; `done` closes the issue. Idempotent.
# Usage: issue-transition.sh <key> <status>
#   status: todo | in-progress | in-review | done
# Depends on: gh, jq.

if ! command -v gh >/dev/null 2>&1; then
  echo "issue-transition.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: issue-transition.sh <key> <status>" >&2
  exit 1
fi

key="$1"
status="$2"

case "${status}" in
  todo|in-progress|in-review|done) ;;
  *) echo "issue-transition.sh: status must be one of todo, in-progress, in-review, done (got: ${status})" >&2; exit 1 ;;
esac

state_labels=("autocode:todo" "autocode:in-progress" "autocode:in-review")

current=$(gh issue view "${key}" --json state,labels --jq '{state: .state, labels: [.labels[].name]}')
gh_state=$(printf '%s' "${current}" | jq -r '.state')

desired_label=""
if [[ "${status}" != "done" ]]; then
  desired_label="autocode:${status}"
fi

remove=()
for lbl in "${state_labels[@]}"; do
  if [[ "${lbl}" != "${desired_label}" ]] \
    && printf '%s' "${current}" | jq -e --arg l "${lbl}" '.labels | any(. == $l)' >/dev/null; then
    remove+=("${lbl}")
  fi
done

remove_csv=""
if [[ "${#remove[@]}" -gt 0 ]]; then
  remove_csv=$(IFS=,; printf '%s' "${remove[*]}")
fi

if [[ "${status}" == "done" ]]; then
  if [[ -n "${remove_csv}" ]]; then
    gh issue edit "${key}" --remove-label "${remove_csv}" >/dev/null
  fi
  if [[ "${gh_state}" != "CLOSED" ]]; then
    gh issue close "${key}" >/dev/null
  fi
else
  gh label create "${desired_label}" --force >/dev/null 2>&1 || true
  edit_args=(issue edit "${key}" --add-label "${desired_label}")
  if [[ -n "${remove_csv}" ]]; then
    edit_args+=(--remove-label "${remove_csv}")
  fi
  gh "${edit_args[@]}" >/dev/null
  if [[ "${gh_state}" == "CLOSED" ]]; then
    gh issue reopen "${key}" >/dev/null
  fi
fi
