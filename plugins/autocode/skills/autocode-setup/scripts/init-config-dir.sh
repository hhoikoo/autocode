#!/usr/bin/env bash
set -euo pipefail

# Initialize the per-repo autocode config directory and wire AUTOCODE_CONFIG_DIR
# into the appropriate Claude Code settings file.
#
# Usage: init-config-dir.sh <config-dir-path>
#
# Picks settings file and persisted value:
#   - committed default (path == <repo-root>/.autocode): write a project-relative
#     ".autocode" into <repo-root>/.claude/settings.json. The settings env block
#     is not shell-expanded and CLAUDE_PROJECT_DIR is not in the Bash env, so an
#     absolute path would be machine-specific and "$CLAUDE_PROJECT_DIR/..." would
#     never resolve; a relative path resolves from the project-root cwd and is
#     safe to commit.
#   - any other path (per-user): write the absolute path into
#     <repo-root>/.claude/settings.local.json (gitignored), since it may live
#     outside the repo.
# Stdout is always the absolute path, for the caller's use within this session.

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <config-dir-path>" >&2
  exit 1
fi

raw_path="$1"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Resolve a leading "~" manually; intentional to avoid bash's tilde expansion on user input.
# shellcheck disable=SC2088
if [[ "${raw_path}" == "~" || "${raw_path}" == "~/"* ]]; then
  raw_path="${HOME}${raw_path:1}"
fi
if [[ "${raw_path}" != /* ]]; then
  raw_path="${repo_root}/${raw_path}"
fi

abs_path=$(cd "$(dirname "${raw_path}")" 2>/dev/null && pwd)/$(basename "${raw_path}") || abs_path="${raw_path}"

mkdir -p "${abs_path}"

default_path="${repo_root}/.autocode"
if [[ "${abs_path}" == "${default_path}" ]]; then
  settings_file="${repo_root}/.claude/settings.json"
  config_value=".autocode"
else
  settings_file="${repo_root}/.claude/settings.local.json"
  config_value="${abs_path}"
fi

mkdir -p "$(dirname "${settings_file}")"
if [[ ! -f "${settings_file}" ]]; then
  echo '{}' > "${settings_file}"
fi

if ! jq -e . "${settings_file}" >/dev/null 2>&1; then
  echo "error: ${settings_file} is not valid JSON" >&2
  exit 1
fi

existing=$(jq -r '.env.AUTOCODE_CONFIG_DIR // empty' "${settings_file}")
if [[ -n "${existing}" && "${existing}" != "${config_value}" ]]; then
  echo "error: ${settings_file} already sets AUTOCODE_CONFIG_DIR=${existing}" >&2
  echo "remove or update it manually, then re-run" >&2
  exit 1
fi

tmp=$(mktemp)
jq --arg v "${config_value}" '.env = (.env // {}) | .env.AUTOCODE_CONFIG_DIR = $v' \
  "${settings_file}" > "${tmp}"
mv "${tmp}" "${settings_file}"

echo "AUTOCODE_CONFIG_DIR=${config_value} written to ${settings_file}" >&2
echo "${abs_path}"
