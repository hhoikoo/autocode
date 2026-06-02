#!/usr/bin/env bash
#
# Create one tracker issue from a rendered body, set its type, and optionally
# link it as a native sub-issue of a parent epic. The design-fanout action calls
# this once per epic and once per unit, passing the rendered body and (for units)
# the epic's GraphQL node id.
#
# Type: when the owning org defines a matching native Issue Type (case-insensitive)
# it is set via PATCH; otherwise a `type:<x>` label is applied as a fallback.
#
# Usage:
#   create-design-issue.sh <repo> <title> <type> <body-file> <org-types-file> [parent-node-id]
#
# <org-types-file> is a TSV of `lowercased-name<TAB>native-name`, empty when the
# owner defines no native types. Prints the created issue number on stdout.

set -euo pipefail

repo="$1"
title="$2"
type="$3"
body_file="$4"
org_types_file="$5"
parent_node="${6:-}"

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

native=$(awk -F'\t' -v w="$(printf '%s' "${type}" | tr '[:upper:]' '[:lower:]')" '$1==w{print $2; exit}' "${org_types_file}")

args=(issue create --repo "${repo}" --title "${title}" --body-file "${body_file}")
if [[ -z "${native}" ]]; then
  tl=$(printf '%s' "${type}" | tr '[:upper:]' '[:lower:]')
  gh label create "type:${tl}" --force >/dev/null 2>&1 || true
  args+=(--label "type:${tl}")
fi

num=$(gh "${args[@]}" | grep -oE '[0-9]+$')

if [[ -n "${native}" ]]; then
  gh api -X PATCH "/repos/${repo}/issues/${num}" -f type="${native}" >/dev/null 2>&1 \
    || echo "warning: created #${num} but could not set native type ${native}" >&2
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
