#!/usr/bin/env bash
set -euo pipefail

# Map a unit issue key or branch to its PR number and state.
# Usage: pr-find.sh <issue-key> [-g <owner/repo>]
#        pr-find.sh --branch <branch> [-g <owner/repo>]
# Stdout: { "number": <int>, "state": "open"|"merged"|"closed" } on match; {} on no match.
# Absence is not an error (exit 0 on no match).
# Depends on: gh, jq.
#
# Issue-key mode uses --search "in:body #<key>" (eventually consistent) plus
# closingIssuesReferences for precise filtering where available.

if ! command -v gh >/dev/null 2>&1; then
  echo "pr-find.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

issue_key=""
branch=""
repo_override=""
repo_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) branch="${2:?Usage: pr-find.sh --branch <branch> [-g <owner/repo>]}"; shift 2 ;;
    -g) repo_override="${2:?Usage: pr-find.sh <issue-key> [-g <owner/repo>]}"; shift 2 ;;
    -*)
      echo "pr-find.sh: unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "${issue_key}" ]]; then
        issue_key="$1"
      else
        echo "pr-find.sh: unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "${issue_key}" && -z "${branch}" ]]; then
  echo "pr-find.sh: require <issue-key> or --branch <branch>" >&2
  exit 1
fi

if [[ -n "${issue_key}" && -n "${branch}" ]]; then
  echo "pr-find.sh: <issue-key> and --branch are mutually exclusive" >&2
  exit 1
fi

if [[ -n "${repo_override}" ]]; then
  owner="${repo_override%%/*}"
  name="${repo_override##*/}"
  repo_args=(--repo "${owner}/${name}")
fi

# Selection rule: prefer first non-closed PR; if all closed, the first.
# shellcheck disable=SC2016
# jq program text, not a shell expansion; single quotes are intentional.
select_filter='
  ( map(.state |= ascii_downcase) ) as $prs |
  ( [ $prs[] | select(.state != "closed") ][0] // $prs[0] ) as $p |
  if $p == null then {} else { number: $p.number, state: $p.state } end
'

if [[ -n "${branch}" ]]; then
  # Branch mode: direct head-match.
  if ! result=$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --head "${branch}" --state all \
    --json number,state 2>&1); then
    echo "pr-find.sh: gh pr list failed: ${result}" >&2
    exit 2
  fi
  printf '%s' "${result}" | jq "${select_filter}"
else
  # Strip a leading '#' so both "42" and "#42" are handled uniformly.
  issue_key="${issue_key#\#}"

  # Issue-key mode: closingIssuesReferences is the precise handle;
  # --search "in:body #<key>" is the accepted simpler path and is eventually consistent.
  if ! result=$(gh pr list ${repo_args[@]+"${repo_args[@]}"} \
    --search "in:body #${issue_key}" \
    --state all \
    --json number,state,closingIssuesReferences 2>&1); then
    echo "pr-find.sh: gh pr list failed: ${result}" >&2
    exit 2
  fi

  # Filter to PRs that genuinely close the issue; fall back to body-search hit if
  # closingIssuesReferences is unavailable.
  # For numeric keys compare against .number (integer); for non-numeric (e.g. BA-1234)
  # compare against a string handle field if present, or fall back to body-search hit.
  if [[ "${issue_key}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${result}" | jq --argjson key "${issue_key}" '
      map(
        . as $pr |
        (
          if (.closingIssuesReferences | length) > 0
          then (.closingIssuesReferences | any(.number == $key))
          else true
          end
        ) |
        if . then $pr else empty end
      ) |
      ( map(.state |= ascii_downcase) ) as $prs |
      ( [ $prs[] | select(.state != "closed") ][0] // $prs[0] ) as $p |
      if $p == null then {} else { number: $p.number, state: $p.state } end
    '
  else
    # Non-numeric key (e.g. Jira-style): closingIssuesReferences has no numeric match;
    # accept any body-search hit (closingIssuesReferences unavailable path).
    printf '%s' "${result}" | jq '
      ( map(.state |= ascii_downcase) ) as $prs |
      ( [ $prs[] | select(.state != "closed") ][0] // $prs[0] ) as $p |
      if $p == null then {} else { number: $p.number, state: $p.state } end
    '
  fi
fi
