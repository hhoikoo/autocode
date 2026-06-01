#!/usr/bin/env bash
set -euo pipefail

# Emit one autocode settings file's JSON on stdout, scoped to either the
# committed `settings.json` or the gitignored `settings.local.json`. The caller
# decides where to land the output.
#
# Usage:
#   write-settings.sh --scope=shared \
#     --issue-tracker=<value> \
#     --git-remote=<value> \
#     [--ci=<value>]
#
#   write-settings.sh --scope=local \
#     --projects-dir=<path>
#
# `--ci=` is optional: when omitted, the field is left out of the JSON so the
# dispatcher's fallback to `provider.git-remote` applies. See
# `autocode/_config/settings-schema.md` for the canonical schema, including
# which top-level namespaces are shared vs local.

scope=""
issue_tracker=""
git_remote=""
ci=""
ci_provided=0
projects_dir=""

for arg in "$@"; do
  case "${arg}" in
    --scope=*)         scope="${arg#*=}" ;;
    --issue-tracker=*) issue_tracker="${arg#*=}" ;;
    --git-remote=*)    git_remote="${arg#*=}" ;;
    --ci=*)            ci="${arg#*=}"; ci_provided=1 ;;
    --projects-dir=*)  projects_dir="${arg#*=}" ;;
    *) echo "write-settings.sh: unknown arg: ${arg}" >&2; exit 1 ;;
  esac
done

case "${scope}" in
  shared|local) ;;
  "") echo "write-settings.sh: --scope=shared|local required" >&2; exit 1 ;;
  *)  echo "write-settings.sh: --scope must be shared or local (got: ${scope})" >&2; exit 1 ;;
esac

if [[ "${scope}" == "shared" ]]; then
  if [[ -z "${issue_tracker}" ]]; then
    echo "write-settings.sh: --issue-tracker=<value> required for --scope=shared" >&2
    exit 1
  fi
  if [[ -z "${git_remote}" ]]; then
    echo "write-settings.sh: --git-remote=<value> required for --scope=shared" >&2
    exit 1
  fi

  provider_json=$(jq -n \
    --arg it "${issue_tracker}" \
    --arg gr "${git_remote}" \
    '{"issue-tracker": $it, "git-remote": $gr}')

  if [[ "${ci_provided}" -eq 1 ]]; then
    provider_json=$(printf '%s' "${provider_json}" | jq --arg ci "${ci}" '. + {ci: $ci}')
  fi

  jq -n \
    --argjson provider "${provider_json}" \
    '{ provider: $provider }'
else
  if [[ -z "${projects_dir}" ]]; then
    echo "write-settings.sh: --projects-dir=<path> required for --scope=local" >&2
    exit 1
  fi

  jq -n \
    --arg projects_dir "${projects_dir}" \
    '{
      paths: {"projects-dir": $projects_dir}
    }'
fi
