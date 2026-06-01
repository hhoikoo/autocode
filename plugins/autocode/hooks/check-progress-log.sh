#!/usr/bin/env bash
set -euo pipefail

# Stop hook. After each turn, if a unit of work is in progress and a new commit
# landed since the last logged entry, nudge the main agent to spawn the
# progress-logger. Mechanical: it detects commits only, writes no log, and
# mutates no code (only its own gitignored state file). Loop-safe via
# stop_hook_active and by recording the SHA on each nudge (one nudge per commit).
#
# Output: exit 0 with `{"decision":"block","reason":...}` to nudge, or exit 0
# with no output to stay silent. Never exit 2 (plugin Stop hooks mishandle it).

input=$(cat)

# Re-entry guard: if we already forced a continuation, let the agent stop.
if [[ "$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)" == "true" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "${project_dir}" ]]; then
  project_dir="$(printf '%s' "${input}" | jq -r '.cwd // empty' 2>/dev/null || echo "")"
fi
if [[ -z "${project_dir}" ]]; then
  project_dir="${PWD}"
fi

context="${project_dir}/.autocode/.impl-context"
[[ -f "${context}" ]] || exit 0   # not a unit-of-work session

git -C "${project_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

cur=$(git -C "${project_dir}" rev-parse HEAD 2>/dev/null || echo "")
[[ -n "${cur}" ]] || exit 0

state="${project_dir}/.autocode/.progress-last-sha"
last=$(cat "${state}" 2>/dev/null || echo "")

if [[ "${cur}" == "${last}" ]]; then
  exit 0   # no new commit since the last nudge/log
fi

# Record now so each new commit nudges exactly once.
printf '%s\n' "${cur}" > "${state}"

slug=$(jq -r '.slug // empty' "${context}" 2>/dev/null || echo "")
log=$(jq -r '.progress_log // empty' "${context}" 2>/dev/null || echo "")

reason="New commit ${cur:0:8} on unit '${slug}' since the last progress entry. Spawn the progress-logger agent in the background (progress_log=${log}, slug=${slug}) with a short note on what this stretch attempted, then stop. If nothing log-worthy happened, skip and stop."

jq -n --arg r "${reason}" '{decision: "block", reason: $r}'
exit 0
