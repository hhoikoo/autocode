#!/usr/bin/env bash
set -euo pipefail

# Reply to a PR review comment. Falls back to posting a regular PR comment
# if the threaded-reply API rejects the request.
# Usage: pr-comment-reply.sh <pr-number> <comment-id> <text>

pr_number="${1:?Usage: pr-comment-reply.sh <pr-number> <comment-id> <text>}"
comment_id="${2:?Usage: pr-comment-reply.sh <pr-number> <comment-id> <text>}"
text="${3:?Usage: pr-comment-reply.sh <pr-number> <comment-id> <text>}"

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

if out=$(gh api -X POST "repos/${repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
    -f body="${text}" --silent 2>&1); then
  exit 0
fi

# Fall back to an unthreaded comment only when the target id is not a review
# comment (HTTP 404/422). Any other failure (auth, network) is surfaced.
case "${out}" in
  *"HTTP 404"*|*"HTTP 422"*)
    echo "pr-comment-reply.sh: threaded reply rejected for ${comment_id}; posting issue-style comment" >&2
    gh api -X POST "repos/${repo}/issues/${pr_number}/comments" \
      -f body="${text}" --silent
    ;;
  *)
    echo "pr-comment-reply.sh: reply failed for ${comment_id}: ${out}" >&2
    exit 2
    ;;
esac
