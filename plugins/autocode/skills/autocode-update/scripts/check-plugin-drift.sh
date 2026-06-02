#!/usr/bin/env bash
set -euo pipefail

# Compare the installed plugin's session-start-parsed surface (skill/agent
# frontmatter shims plus the inline bootstrap skills and hooks) against the
# freshly-pulled ~/.autocode/ checkout.
#
# autocode-update's git pull refreshes ~/.autocode/ only; the installed plugin
# updates through Claude Code's plugin channel, not this pull. When the two
# diverge the running plugin is stale: frontmatter and bootstrap changes (this
# skill's own description included) sit in ~/.autocode/ but will not load until
# the plugin is updated and the session restarts.
#
# Output (stdout, JSON): {"stale": <bool>, "files": [<diff lines>]}.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(cd "${script_dir}/../../.." && pwd)   # scripts -> autocode-update -> skills -> plugin root
canonical="${HOME}/.autocode/plugins/autocode"

emit() { jq -n --argjson stale "$1" --argjson files "$2" '{stale: $stale, files: $files}'; }

if [[ ! -d "${canonical}" ]]; then
  echo "warning: ${canonical} not found; skipping plugin drift check" >&2
  emit false '[]'
  exit 0
fi

# Symlinked dev checkout: the installed plugin is the canonical tree, so there
# is no separate channel to drift.
if [[ "${plugin_root}" -ef "${canonical}" ]]; then
  emit false '[]'
  exit 0
fi

diffs=""
for sub in skills agents hooks; do
  out=$(diff -rq "${plugin_root}/${sub}" "${canonical}/${sub}" 2>/dev/null || true)
  [[ -n "${out}" ]] && diffs+="${out}"$'\n'
done

if [[ -z "${diffs}" ]]; then
  emit false '[]'
else
  files=$(printf '%s' "${diffs}" | sed '/^$/d' | jq -R . | jq -s .)
  emit true "${files}"
fi
exit 0
