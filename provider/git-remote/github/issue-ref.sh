#!/usr/bin/env bash
set -euo pipefail

# Resolve the git-remote-native issue number to close for a tracker key.
# Usage: issue-ref.sh <tracker-key>
# Stdout: the GitHub issue number on a single line, or empty when there is
#         nothing on this remote to close.
#
# A close reference (`Closes #N`) only auto-closes when N is a GitHub issue
# number. When the issue tracker is GitHub Issues the tracker key already is
# that number; when it is another tracker (e.g. Jira `PROJ-123`) the key is not
# a GitHub number, so the only thing GitHub can close is a mirrored issue.

tracker_key="${1:?Usage: issue-ref.sh <tracker-key>}"

# Numeric key: the tracker is GitHub Issues, so the key is the close target.
if [[ "${tracker_key}" =~ ^[0-9]+$ ]]; then
  printf '%s\n' "${tracker_key}"
  exit 0
fi

# Non-numeric key: search for a mirrored GitHub issue that references the key in
# its title or body. Emit its number, or nothing when no mirror exists.
number=$(gh issue list --search "${tracker_key} in:title,body" --state all --limit 1 \
  --json number --jq '.[0].number // empty' 2>/dev/null || true)

if [[ -n "${number}" ]]; then
  echo "issue-ref.sh: resolved tracker key ${tracker_key} to mirrored issue #${number}" >&2
  printf '%s\n' "${number}"
else
  echo "issue-ref.sh: no mirrored GitHub issue for tracker key ${tracker_key}; nothing to close" >&2
fi
exit 0
