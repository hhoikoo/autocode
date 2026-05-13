#!/usr/bin/env bash
set -euo pipefail

# Initialize the per-repo autocode config directory and wire AUTOCODE_CONFIG_DIR
# into the appropriate Claude Code settings file.
#
# Usage: init-config-dir.sh <config-dir-path>
#
# Picks settings file:
#   - <repo-root>/.claude/settings.json       if path == <repo-root>/.autocode (committed default)
#   - <repo-root>/.claude/settings.local.json otherwise (per-user)

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
else
  settings_file="${repo_root}/.claude/settings.local.json"
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
if [[ -n "${existing}" && "${existing}" != "${abs_path}" ]]; then
  echo "error: ${settings_file} already sets AUTOCODE_CONFIG_DIR=${existing}" >&2
  echo "remove or update it manually, then re-run" >&2
  exit 1
fi

tmp=$(mktemp)
jq --arg v "${abs_path}" '.env = (.env // {}) | .env.AUTOCODE_CONFIG_DIR = $v' \
  "${settings_file}" > "${tmp}"
mv "${tmp}" "${settings_file}"

echo "AUTOCODE_CONFIG_DIR=${abs_path} written to ${settings_file}" >&2
echo "${abs_path}"
