#!/usr/bin/env bash
set -euo pipefail

# Clone the autocode repo to ~/.autocode/ (shallow, single-branch).
# Idempotent: exits 0 with "already-installed" on stderr if ~/.autocode/ is a git checkout.

REPO_URL="https://github.com/hhoikoo/autocode.git"
TARGET="${HOME}/.autocode"

if [[ -d "${TARGET}/.git" ]]; then
  echo "already-installed" >&2
  exit 0
fi

if [[ -e "${TARGET}" ]]; then
  echo "error: ${TARGET} exists but is not a git checkout" >&2
  echo "delete it and re-run /autocode-setup" >&2
  exit 1
fi

git clone --depth 1 --single-branch --branch main "${REPO_URL}" "${TARGET}"
git -C "${TARGET}" remote set-url --push origin DISABLED

echo "cloned ${REPO_URL} -> ${TARGET}" >&2
