#!/usr/bin/env bash
set -euo pipefail

# Point this repo's git at .githooks/ for hooks. Idempotent.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

git -C "${REPO_DIR}" config core.hooksPath .githooks
echo "git core.hooksPath -> .githooks" >&2
