#!/usr/bin/env bash
set -euo pipefail

# View a pull request. Defaults to the PR for the current branch.
# Usage: pr-view.sh [--json <comma-separated fields>] [<pr-number>]
# Stdout: text or JSON (with --json), as returned by `gh pr view`.

gh pr view "$@"
