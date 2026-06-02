#!/usr/bin/env bash
set -euo pipefail

# Create a GitHub issue, optionally linked as a sub-issue of a parent.
# Usage: issue-create.sh -t <type> -s <summary> [-b <body-file>] [-P <parent>] \
#                  [-a <assignee>] [-S <points>] [-g <owner/repo>] [-l <label>]...
# Depends on: gh, jq.
#
# Issue type: set as a native GitHub Issue Type by name (e.g. autocode `bug` ->
# GitHub `Bug`) via a repo-scoped REST write, then confirmed by reading it back.
# If the type did not take (the org defines no such type, or none at all as on
# user repos) it falls back to a `type:<x>` label. Avoids the org-scoped
# issue-types read, which a workflow GITHUB_TOKEN cannot perform.

if ! command -v gh >/dev/null 2>&1; then
  echo "issue-create.sh: gh CLI not on PATH; install GitHub CLI and run 'gh auth login'" >&2
  exit 2
fi

type=""
summary=""
body_file=""
parent=""
assignee=""
repo_override=""
labels=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) type="${2:-}"; shift 2 ;;
    -s) summary="${2:-}"; shift 2 ;;
    -b) body_file="${2:-}"; shift 2 ;;
    -P) parent="${2:-}"; shift 2 ;;
    -a) assignee="${2:-}"; shift 2 ;;
    # Story points: accepted for cross-provider contract parity; ignored.
    -S) shift 2 ;;
    -g) repo_override="${2:-}"; shift 2 ;;
    -l) labels+=("${2:-}"); shift 2 ;;
    *) echo "issue-create.sh: unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${type}" ]]; then
  echo "issue-create.sh: -t <type> is required" >&2
  exit 1
fi
if [[ -z "${summary}" ]]; then
  echo "issue-create.sh: -s <summary> is required" >&2
  exit 1
fi

if [[ -n "${body_file}" && ! -f "${body_file}" ]]; then
  echo "issue-create.sh: body file not found: ${body_file}" >&2
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

type_lower=$(printf '%s' "${type}" | tr '[:upper:]' '[:lower:]')
# Issue Types are named in Title case (Bug, Task, ...); match that when setting.
type_name=$(printf '%s' "${type_lower}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

args=(issue create --title "${summary}")
if [[ -n "${repo_override}" ]]; then
  args+=(--repo "${repo_override}")
fi

if [[ -n "${body_file}" ]]; then
  args+=(--body-file "${body_file}")
else
  args+=(--body "")
fi

if [[ -n "${assignee}" ]]; then
  args+=(--assignee "${assignee}")
fi

for label in "${labels[@]+"${labels[@]}"}"; do
  args+=(--label "${label}")
done

url=$(gh "${args[@]}")
child_number=$(printf '%s' "${url}" | grep -oE '[0-9]+$' || true)

if [[ -z "${child_number}" ]]; then
  echo "issue-create.sh: could not parse issue number from gh output: ${url}" >&2
  exit 2
fi

# Set the native Issue Type by name (repo-scoped issues:write; no org read). An
# unknown type name is silently dropped, so confirm by reading it back; apply a
# type:<x> label only when the type did not take.
gh api -X PATCH "/repos/${owner}/${name}/issues/${child_number}" -f type="${type_name}" >/dev/null 2>&1 || true
applied_type=$(gh api "/repos/${owner}/${name}/issues/${child_number}" --jq '.type.name // empty' 2>/dev/null || true)
if [[ -z "${applied_type}" ]]; then
  gh label create "type:${type_lower}" --force >/dev/null 2>&1 || true
  edit_args=(issue edit "${child_number}" --add-label "type:${type_lower}")
  if [[ -n "${repo_override}" ]]; then
    edit_args+=(--repo "${repo_override}")
  fi
  gh "${edit_args[@]}" >/dev/null
fi

# Link as sub-issue when a parent was requested.
if [[ -n "${parent}" ]]; then
  get_issue_id() {
    # shellcheck disable=SC2016
    gh api graphql \
      -H "GraphQL-Features:sub_issues" \
      -f query='
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            issue(number: $number) { id }
          }
        }
      ' \
      -f owner="${owner}" \
      -f name="${name}" \
      -F number="$1" \
      --jq '.data.repository.issue.id'
  }

  parent_id=$(get_issue_id "${parent}" || echo "")
  child_id=$(get_issue_id "${child_number}" || echo "")

  if [[ -n "${parent_id}" && "${parent_id}" != "null" && -n "${child_id}" && "${child_id}" != "null" ]]; then
    # shellcheck disable=SC2016
    gh api graphql \
      -H "GraphQL-Features:sub_issues" \
      -f query='
        mutation($parentId: ID!, $childId: ID!) {
          addSubIssue(input: { issueId: $parentId, subIssueId: $childId }) {
            subIssue { number }
          }
        }
      ' \
      -f parentId="${parent_id}" \
      -f childId="${child_id}" \
      >/dev/null 2>&1 || echo "issue-create.sh: warning: could not link #${child_number} as sub-issue of #${parent}" >&2
  else
    echo "issue-create.sh: warning: could not resolve parent/child node ids; skipping sub-issue link" >&2
  fi
fi

printf '%s\n' "${child_number}"
