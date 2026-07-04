#!/usr/bin/env bash
set -euo pipefail

# Fetch unresolved review-thread ids for a PR.
# Usage: pr-thread-list.sh <pr-number>
# Stdout: JSON array of { id, path, body_preview } for each unresolved thread.

pr_number="${1:?Usage: pr-thread-list.sh <pr-number>}"
owner=$(gh repo view --json owner -q .owner.login)
name=$(gh repo view --json name -q .name)

# $owner, $name, $number are GraphQL variable references, not shell variables
# shellcheck disable=SC2016
gh api graphql \
  -F owner="${owner}" \
  -F name="${name}" \
  -F number="${pr_number}" \
  -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              body
              path
            }
          }
        }
      }
    }
  }
}' --jq '
  [ .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false)
    | {
        id,
        path: (.comments.nodes[0].path // ""),
        body_preview: ((.comments.nodes[0].body // "")[:80])
      }
  ]'
