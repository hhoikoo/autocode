#!/usr/bin/env bash
set -euo pipefail

# Pull the latest autocode into ~/.autocode/.
# Refuses to run if ~/.autocode/ is missing or not on main.

TARGET="${HOME}/.autocode"

if [[ ! -d "${TARGET}/.git" ]]; then
  echo "error: ${TARGET} is not a git checkout; run /autocode-setup" >&2
  exit 1
fi

current_branch=$(git -C "${TARGET}" rev-parse --abbrev-ref HEAD)
if [[ "${current_branch}" != "main" ]]; then
  echo "error: ${TARGET} is on branch '${current_branch}', not 'main'" >&2
  echo "this looks like an /autocode-test feature checkout" >&2
  echo "switch back with: git -C ${TARGET} switch main" >&2
  exit 1
fi

git -C "${TARGET}" fetch origin main --quiet

# A managed checkout's local main should always be an ancestor of origin/main.
# When it is not, origin/main has been rewritten (force-push, history surgery)
# and `git pull --ff-only` would fail with an opaque error. SKILL.md handles
# the user prompt.
if ! git -C "${TARGET}" merge-base --is-ancestor main origin/main 2>/dev/null; then
  ahead=$(git -C "${TARGET}" rev-list --count origin/main..main)
  behind=$(git -C "${TARGET}" rev-list --count main..origin/main)
  dirty=$(git -C "${TARGET}" status --porcelain)

  echo "error: ${TARGET}/main has diverged from origin/main (${ahead} ahead, ${behind} behind)" >&2
  echo "this usually means origin/main was force-pushed; ~/.autocode/ is a managed checkout and should not carry local commits" >&2
  if [[ -n "${dirty}" ]]; then
    echo "uncommitted working-tree changes are present; resolve them before resetting" >&2
  fi
  echo "to discard the diverged history and match origin run: git -C ${TARGET} reset --hard origin/main" >&2
  exit 1
fi

behind=$(git -C "${TARGET}" rev-list --count main..origin/main)
git -C "${TARGET}" pull --ff-only origin main --quiet

date +%s > "${TARGET}/.last-fetch"
rm -f "${TARGET}/.update-available"

echo "pulled ${behind} commit(s) into ${TARGET}" >&2
