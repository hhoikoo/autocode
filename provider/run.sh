#!/usr/bin/env bash
set -euo pipefail

# Dispatch a provider call. See provider/CLAUDE.md for the full contract.
#
# Usage: provider/run.sh <provider-type> <feature> [args...]
#
# Fallback: when <provider-type> is `ci` and .provider.ci is missing or empty,
# fall back to .provider.git-remote (CI typically lives with the git remote).

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <provider-type> <feature> [args...]" >&2
  exit 1
fi

provider_type="$1"
feature="$2"
shift 2

: "${AUTOCODE_CONFIG_DIR:?AUTOCODE_CONFIG_DIR is unset; run /autocode-setup}"

settings_file="${AUTOCODE_CONFIG_DIR}/settings.json"
if [[ ! -f "${settings_file}" ]]; then
  echo "provider/run.sh: missing ${settings_file}; run /autocode-setup" >&2
  exit 1
fi

if ! jq -e . "${settings_file}" >/dev/null 2>&1; then
  echo "provider/run.sh: ${settings_file} is not valid JSON" >&2
  exit 1
fi

provider=$(jq -r --arg t "${provider_type}" '.provider[$t] // empty' "${settings_file}")
if [[ -z "${provider}" && "${provider_type}" == "ci" ]]; then
  provider=$(jq -r '.provider["git-remote"] // empty' "${settings_file}")
  if [[ -z "${provider}" ]]; then
    echo "provider/run.sh: settings.json missing both .provider.ci and .provider.git-remote" >&2
    exit 1
  fi
fi
if [[ -z "${provider}" ]]; then
  echo "provider/run.sh: settings.json missing .provider.${provider_type}" >&2
  exit 1
fi

script="${HOME}/.autocode/provider/${provider_type}/${provider}/${feature}.sh"
if [[ ! -x "${script}" ]]; then
  if [[ -f "${script}" ]]; then
    echo "provider/run.sh: ${script} is not executable" >&2
  else
    echo "provider/run.sh: no provider script at ${script}" >&2
  fi
  exit 1
fi

exec "${script}" "$@"
