#!/usr/bin/env bash
set -euo pipefail

# Resolve one or more PR review threads by node id. Tolerates already-resolved threads.
# Usage: pr-thread-resolve.sh <thread-id> [<thread-id>...]

if [[ $# -eq 0 ]]; then
  echo "Usage: pr-thread-resolve.sh <thread-id> [<thread-id>...]" >&2
  exit 1
fi

failed=0
for thread_id in "$@"; do
  # $threadId is a GraphQL variable reference, not a shell variable
  # shellcheck disable=SC2016
  if out=$(gh api graphql \
      -F threadId="${thread_id}" \
      -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' --jq '.data.resolveReviewThread.thread.isResolved' 2>&1); then
    echo "pr-thread-resolve.sh: ${thread_id} -> resolved=${out}" >&2
  else
    if echo "${out}" | grep -qiE 'already resolved|thread is resolved'; then
      echo "pr-thread-resolve.sh: ${thread_id} already resolved" >&2
      continue
    fi
    echo "pr-thread-resolve.sh: failed to resolve ${thread_id}: ${out}" >&2
    failed=1
  fi
done

exit "${failed}"
