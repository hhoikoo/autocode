#!/usr/bin/env bash
set -euo pipefail

# Fetch all comments on a PR (review-line + issue-style), merged into one JSON array.
# Usage: pr-comment-list.sh <pr-number>
# Stdout: JSON array of
#   { id, author, body, path, line, created_at, in_reply_to_id, kind }
# where kind is "review" or "issue".

pr_number="${1:?Usage: pr-comment-list.sh <pr-number>}"
shift
if [[ $# -gt 0 ]]; then
  echo "pr-comment-list.sh: unexpected argument: $1" >&2
  exit 1
fi
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

review=$(gh api --paginate "repos/${repo}/pulls/${pr_number}/comments" \
  | jq -s '
      (add // []) |
      [ .[] | {
          id: (.id | tostring),
          author: (.user.login // ""),
          body: (.body // ""),
          path: (.path // ""),
          line: (.line // .original_line // null),
          created_at: (.created_at // ""),
          in_reply_to_id: ((.in_reply_to_id // "") | tostring | sub("^0$"; "")),
          kind: "review"
        }
      ]')

issue=$(gh api --paginate "repos/${repo}/issues/${pr_number}/comments" \
  | jq -s '
      (add // []) |
      [ .[] | {
          id: (.id | tostring),
          author: (.user.login // ""),
          body: (.body // ""),
          path: "",
          line: null,
          created_at: (.created_at // ""),
          in_reply_to_id: "",
          kind: "issue"
        }
      ]')

jq -nc --argjson r "${review}" --argjson i "${issue}" '$r + $i'
