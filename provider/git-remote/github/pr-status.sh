#!/usr/bin/env bash
set -euo pipefail

# Emit one typed JSON object for a PR (state, CI, review, mergeable).
# Usage: pr-status.sh <pr-number> [-g <owner/repo>]
# Depends on: gh, jq.

if ! command -v gh >/dev/null 2>&1; then
  echo "pr-status.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

pr_number=""
repo_override=""
repo_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g) repo_override="${2:?Usage: pr-status.sh <pr-number> [-g <owner/repo>]}"; shift 2 ;;
    -*)
      echo "pr-status.sh: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "${pr_number}" ]]; then
        pr_number="$1"
      else
        echo "pr-status.sh: unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

: "${pr_number:?Usage: pr-status.sh <pr-number> [-g <owner/repo>]}"

if [[ -n "${repo_override}" ]]; then
  owner="${repo_override%%/*}"
  name="${repo_override##*/}"
  repo_args=(--repo "${owner}/${name}")
fi

# Single call per check (DESIGN decision 7 / runtime-flow step 5).
raw=$(gh pr view "${pr_number}" ${repo_args[@]+"${repo_args[@]}"} \
  --json state,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,isDraft,url,number \
  2>/dev/null) || {
  echo "pr-status.sh: PR #${pr_number} not found or gh call failed" >&2
  exit 1
}

# Normalize to typed contract object.
# CI rollup computed inline from statusCheckRollup (single gh call).
printf '%s' "${raw}" | jq '
  (.statusCheckRollup // []) as $r |
  (
    if ($r | length) == 0 then "none"
    elif ($r | any(
           (.conclusion // .state // "") | ascii_downcase |
           . == "failure" or . == "timed_out" or . == "cancelled" or
           . == "action_required" or . == "startup_failure" or . == "error"
         )) then "failing"
    elif ($r | any(
           ((.status // .state // "") | ascii_downcase) as $s |
           $s == "in_progress" or $s == "queued" or $s == "pending" or
           $s == "waiting" or $s == "requested" or
           ((.conclusion // null) == null and $s != "completed")
         )) then "pending"
    else "passing"
    end
  ) as $ci |
  {
    number: .number,
    url: .url,
    state: (.state | ascii_downcase),
    isDraft: .isDraft,
    mergeable: (.mergeable | ascii_downcase),
    mergeStateStatus: (.mergeStateStatus | ascii_downcase),
    ci: $ci,
    reviewDecision: (
      (.reviewDecision // "" | ascii_downcase) |
      if . == "" then "none" else . end
    )
  }
'
