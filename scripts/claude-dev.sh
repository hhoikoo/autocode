#!/usr/bin/env bash
set -euo pipefail

# Launch Claude Code with the local plugin tree loaded.
# Use for testing in-repo plugin edits without going through the marketplace install.
# Runtime resolution of @~/.autocode/... shim references still requires /autocode-test
# to have checked the working branch out inside ~/.autocode/.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec claude --plugin-dir "${REPO_DIR}/plugins/autocode" "$@"
