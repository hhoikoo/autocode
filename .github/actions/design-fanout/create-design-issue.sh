#!/usr/bin/env bash
#
# Create one tracker issue from a rendered body, set its type, and optionally
# link it as a native sub-issue of a parent epic. The design-fanout action calls
# this once per epic and once per unit, passing the rendered body and (for units)
# the epic's GraphQL node id.
#
# Type: set as a native Issue Type by name via a repo-scoped REST write, then
# confirmed by reading it back. If the type did not take (the org defines no such
# type, or none at all), a `type:<x>` label is applied as a fallback. Avoids the
# org-scoped issue-types read, which the workflow GITHUB_TOKEN cannot perform.
#
# Usage:
#   create-design-issue.sh <repo> <title> <type> <body-file> [parent-node-id]
#
# Prints the created issue number on stdout.

set -euo pipefail

repo="$1"
title="$2"
type="$3"
body_file="$4"
parent_node="${5:-}"

owner="${repo%%/*}"
name="${repo##*/}"

# Opaque GraphQL node id (I_kwDO...) for a given issue number; the REST integer id
# is not a valid GraphQL ID and will not resolve in addSubIssue.
node_id() {  # $1=issue number
  # shellcheck disable=SC2016  # $-tokens are GraphQL variables, not shell expansions
  gh api graphql -H "GraphQL-Features:sub_issues" \
    -f query='query($o:String!,$n:String!,$num:Int!){repository(owner:$o,name:$n){issue(number:$num){id}}}' \
    -f o="${owner}" -f n="${name}" -F num="$1" --jq '.data.repository.issue.id'
}

type_lower=$(printf '%s' "${type}" | tr '[:upper:]' '[:lower:]')
# Issue Types are named in Title case (Bug, Task, ...); match that when setting.
type_name=$(printf '%s' "${type_lower}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

num=$(gh issue create --repo "${repo}" --title "${title}" --body-file "${body_file}" | grep -oE '[0-9]+$')

# Set the native Issue Type by name (repo-scoped); an unknown name is silently
# dropped, so confirm by reading it back and fall back to a type:<x> label.
gh api -X PATCH "/repos/${repo}/issues/${num}" -f type="${type_name}" >/dev/null 2>&1 || true
applied=$(gh api "/repos/${repo}/issues/${num}" --jq '.type.name // empty' 2>/dev/null || true)
if [[ -z "${applied}" ]]; then
  gh label create "type:${type_lower}" --repo "${repo}" --force >/dev/null 2>&1 || true
  gh issue edit "${num}" --repo "${repo}" --add-label "type:${type_lower}" >/dev/null
fi

if [[ -n "${parent_node}" ]]; then
  child=$(node_id "${num}")
  # shellcheck disable=SC2016  # $-tokens are GraphQL variables, not shell expansions
  gh api graphql -H "GraphQL-Features:sub_issues" \
    -f query='mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){subIssue{number}}}' \
    -f p="${parent_node}" -f c="${child}" >/dev/null 2>&1 \
    || echo "warning: created #${num} but could not link to parent epic" >&2
fi

printf '%s\n' "${num}"
