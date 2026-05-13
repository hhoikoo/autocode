#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook.
#
# Output contract: JSON systemMessage on stdout when ~/.autocode/ needs
# attention (missing, non-main branch, or out of date); nothing otherwise.
# Always exits 0 so it never blocks the session.

TARGET="${HOME}/.autocode"
FETCH_CACHE="${TARGET}/.last-fetch"
UPDATE_FLAG="${TARGET}/.update-available"
FETCH_TTL=$((24 * 60 * 60))

emit_warning() {
  local msg="$1"
  jq -n --arg m "${msg}" '{systemMessage: $m}'
}

if [[ ! -d "${TARGET}/.git" ]]; then
  emit_warning "autocode: ~/.autocode/ not found. Run /autocode-setup."
  exit 0
fi

current_branch=$(git -C "${TARGET}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
if [[ "${current_branch}" != "main" ]]; then
  emit_warning "autocode: ~/.autocode/ is on '${current_branch}', not 'main'. Switch back with: git -C ~/.autocode switch main"
  exit 0
fi

# Surface a stale update-available flag without spending another network call.
if [[ -f "${UPDATE_FLAG}" ]]; then
  emit_warning "autocode: updates available on origin/main. Run /autocode-update."
  exit 0
fi

# Cap remote checks to once per FETCH_TTL so session starts stay cheap.
now=$(date +%s)
if [[ -f "${FETCH_CACHE}" ]]; then
  last=$(cat "${FETCH_CACHE}" 2>/dev/null || echo 0)
  if (( now - last < FETCH_TTL )); then
    exit 0
  fi
fi

remote_sha=$(git -C "${TARGET}" ls-remote --quiet origin main 2>/dev/null | awk 'NR==1{print $1}')
if [[ -z "${remote_sha}" ]]; then
  # Offline or remote unreachable. Do not warn and do not update the cache (so the next session retries).
  exit 0
fi

local_sha=$(git -C "${TARGET}" rev-parse main 2>/dev/null || echo "")
echo "${now}" > "${FETCH_CACHE}"

if [[ -n "${local_sha}" && "${remote_sha}" != "${local_sha}" ]]; then
  echo "behind" > "${UPDATE_FLAG}"
  emit_warning "autocode: updates available on origin/main. Run /autocode-update."
fi

exit 0
