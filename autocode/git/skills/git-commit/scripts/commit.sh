#!/usr/bin/env bash
set -euo pipefail

# Subcommands:
#   gather              -> emit JSON describing repo state
#   commit <msg-file>   -> git commit -F <msg-file>
#   push                -> git push

usage() {
  echo "usage: commit.sh <gather|commit <msg-file>|push>" >&2
  exit 2
}

gather() {
  local porcelain
  porcelain="$(git status --porcelain=v1 || true)"

  local staged=() unstaged=() untracked=()
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local x="${line:0:1}"
    local y="${line:1:1}"
    local path="${line:3}"
    if [[ "${x}" == "?" && "${y}" == "?" ]]; then
      untracked+=("${path}")
      continue
    fi
    if [[ "${x}" != " " && "${x}" != "?" ]]; then
      staged+=("${path}")
    fi
    if [[ "${y}" != " " && "${y}" != "?" ]]; then
      unstaged+=("${path}")
    fi
  done <<< "${porcelain}"

  local log_recent
  log_recent="$(git log --oneline -5 2>/dev/null || true)"

  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

  local upstream=""
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  local ahead=0 behind=0
  if [[ -n "${upstream}" ]]; then
    local counts
    counts="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo "0	0")"
    behind="${counts%%$'\t'*}"
    ahead="${counts##*$'\t'}"
  fi

  jq -n \
    --argjson staged "$(printf '%s\n' "${staged[@]+"${staged[@]}"}" | jq -R . | jq -s .)" \
    --argjson unstaged "$(printf '%s\n' "${unstaged[@]+"${unstaged[@]}"}" | jq -R . | jq -s .)" \
    --argjson untracked "$(printf '%s\n' "${untracked[@]+"${untracked[@]}"}" | jq -R . | jq -s .)" \
    --argjson log_recent "$(printf '%s\n' "${log_recent}" | jq -R . | jq -s 'map(select(length > 0))')" \
    --arg current_branch "${current_branch}" \
    --arg upstream "${upstream}" \
    --argjson ahead "${ahead:-0}" \
    --argjson behind "${behind:-0}" \
    '{
      staged: ($staged | map(select(length > 0))),
      unstaged: ($unstaged | map(select(length > 0))),
      untracked: ($untracked | map(select(length > 0))),
      log_recent: $log_recent,
      current_branch: $current_branch,
      upstream: $upstream,
      ahead: $ahead,
      behind: $behind
    }'
}

do_commit() {
  local msg_file="${1:?msg-file required}"
  if [[ ! -f "${msg_file}" ]]; then
    echo "commit.sh: message file not found: ${msg_file}" >&2
    exit 1
  fi
  git commit -F "${msg_file}"
}

do_push() {
  git push
}

main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
    gather) gather ;;
    commit) do_commit "$@" ;;
    push)   do_push ;;
    *)      usage ;;
  esac
}

main "$@"
