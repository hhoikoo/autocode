#!/usr/bin/env bash
set -euo pipefail

# Run by .githooks/pre-commit and CI.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

fail=0
note() { echo "[shape] $*" >&2; }
err()  { echo "[shape] ERROR: $*" >&2; fail=1; }

# Bootstrap exception allowlist: plugin-native skills that do not have a real-file pair.
bootstrap_skills=("autocode-setup" "autocode-update")

is_bootstrap_skill() {
  local name="$1"
  for b in "${bootstrap_skills[@]}"; do
    [[ "${name}" == "${b}" ]] && return 0
  done
  return 1
}

has_frontmatter() {
  # Real definition files must not carry YAML frontmatter.
  # Frontmatter is detected by a leading '---' on line 1.
  local file="$1"
  [[ "$(head -n 1 "${file}")" == "---" ]]
}

check_skill_shim() {
  local shim="$1"
  local name
  name=$(basename "$(dirname "${shim}")")

  if is_bootstrap_skill "${name}"; then
    note "skill '${name}': bootstrap exception, skipping shim/real check"
    return
  fi

  # Real file must exist somewhere under autocode/<feature-set>/skills/<name>/SKILL.md
  local matches
  matches=$(find autocode -mindepth 4 -maxdepth 4 -type f \
            -path "autocode/*/skills/${name}/SKILL.md" 2>/dev/null || true)
  local count
  count=$(printf '%s\n' "${matches}" | grep -c '.' || true)

  if [[ "${count}" -eq 0 ]]; then
    err "skill '${name}' has shim but no real file under autocode/*/skills/${name}/SKILL.md"
    return
  fi
  if [[ "${count}" -gt 1 ]]; then
    err "skill '${name}' has ${count} real files; names must be unique across feature-sets"
    printf '%s\n' "${matches}" | sed 's/^/  /' >&2
    return
  fi

  local real="${matches}"
  if has_frontmatter "${real}"; then
    err "skill '${name}': real file ${real} must not carry frontmatter (only the shim does)"
  fi

  # Shim body must read the located real file via its exact @~/.autocode/ path.
  if ! grep -qF "@~/.autocode/${real}" "${shim}"; then
    err "skill '${name}': shim ${shim} missing read line '@~/.autocode/${real}'"
  fi
}

check_agent_shim() {
  local shim="$1"
  local name
  name=$(basename "${shim}" .md)

  local matches
  matches=$(find autocode -mindepth 3 -maxdepth 3 -type f \
            -path "autocode/*/agents/${name}.md" 2>/dev/null || true)
  local count
  count=$(printf '%s\n' "${matches}" | grep -c '.' || true)

  if [[ "${count}" -eq 0 ]]; then
    err "agent '${name}' has shim but no real file under autocode/*/agents/${name}.md"
    return
  fi
  if [[ "${count}" -gt 1 ]]; then
    err "agent '${name}' has ${count} real files; names must be unique across feature-sets"
    return
  fi

  local real="${matches}"
  if has_frontmatter "${real}"; then
    err "agent '${name}': real file ${real} must not carry frontmatter (only the shim does)"
  fi

  # Shim body must read the located real file via its exact @~/.autocode/ path.
  if ! grep -qF "@~/.autocode/${real}" "${shim}"; then
    err "agent '${name}': shim ${shim} missing read line '@~/.autocode/${real}'"
  fi
}

# 1. Skill shims
note "checking skill shims"
shopt -s nullglob
for shim in plugins/autocode/skills/*/SKILL.md; do
  check_skill_shim "${shim}"
done

# 2. Agent shims
note "checking agent shims"
for shim in plugins/autocode/agents/*.md; do
  check_agent_shim "${shim}"
done

# 3. Reverse pass: every real skill/agent must have a shim, else it ships nowhere.
note "checking every real skill/agent has a shim"
for real in autocode/*/skills/*/SKILL.md; do
  name=$(basename "$(dirname "${real}")")
  if [[ ! -f "plugins/autocode/skills/${name}/SKILL.md" ]]; then
    err "real skill '${name}' (${real}) has no shim under plugins/autocode/skills/${name}/SKILL.md"
  fi
done
for real in autocode/*/agents/*.md; do
  name=$(basename "${real}" .md)
  if [[ ! -f "plugins/autocode/agents/${name}.md" ]]; then
    err "real agent '${name}' (${real}) has no shim under plugins/autocode/agents/${name}.md"
  fi
done

# 4. design-fanout: the plugin template is canonical; the live .github copy the
# repo runs must stay byte-identical (workflows can't be symlinks, so gate it).
note "checking design-fanout live copy matches canonical template"
fanout_tmpl="plugins/autocode/templates/autocreate-design-doc-issue"
if ! diff -r ".github/actions/design-fanout" \
     "${fanout_tmpl}/.github/actions/design-fanout" >/dev/null 2>&1; then
  err "design-fanout drift: .github/actions/design-fanout differs from canonical ${fanout_tmpl}/.github/actions/design-fanout"
fi
if ! diff ".github/workflows/autocreate-design-doc-issue.yml" \
     "${fanout_tmpl}/.github/workflows/autocreate-design-doc-issue.yml" >/dev/null 2>&1; then
  err "design-fanout drift: .github/workflows/autocreate-design-doc-issue.yml differs from canonical ${fanout_tmpl}/.github/workflows/autocreate-design-doc-issue.yml"
fi

# 5. Every autocode/<feature-set>/ has a CLAUDE.md
note "checking feature-set CLAUDE.md files"
for dir in autocode/*/; do
  if [[ ! -f "${dir}CLAUDE.md" ]]; then
    err "missing ${dir}CLAUDE.md"
  fi
done

# 6. Engineering-minimalism invariants survive in the forced output style.
# The ladder reaches plugin users only through concise.md (force-for-plugin +
# the per-agent read line); a careless edit must not silently gut it.
note "checking leanness invariants in concise.md"
style="autocode/_config/output-styles/concise.md"
if [[ ! -f "${style}" ]]; then
  err "missing ${style}"
else
  leanness_invariants=(
    "## Engineering minimalism"
    "Does this need to exist"
    "input validation at trust boundaries"
    "leanness:"
    "ONE runnable check"
  )
  for phrase in "${leanness_invariants[@]}"; do
    if ! grep -qF "${phrase}" "${style}"; then
      err "concise.md missing leanness invariant: \"${phrase}\""
    fi
  done
fi

# 7. Plugin manifest carries a version (the CLAUDE.md SSOT row points here).
note "checking plugin.json version field"
plugin_manifest="plugins/autocode/.claude-plugin/plugin.json"
if [[ ! -f "${plugin_manifest}" ]]; then
  err "missing ${plugin_manifest}"
elif ! grep -Eq '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "${plugin_manifest}"; then
  err "missing non-empty \"version\" in ${plugin_manifest}"
fi

# 8. Shellcheck all shell scripts under tracked locations.
note "shellchecking shell scripts"
scripts=()
while IFS= read -r f; do
  scripts+=("${f}")
done < <(find provider plugins/autocode autocode .github .githooks scripts -type f -name '*.sh' 2>/dev/null | sort)

if ! command -v shellcheck >/dev/null 2>&1; then
  err "shellcheck not installed; install it (brew install shellcheck) and re-run"
elif [[ "${#scripts[@]}" -gt 0 ]]; then
  if ! shellcheck "${scripts[@]}"; then
    fail=1
  fi
fi

# Pre-commit hook is a shell script too even though it has no extension.
if [[ -f .githooks/pre-commit ]] && command -v shellcheck >/dev/null 2>&1; then
  if ! shellcheck -s bash .githooks/pre-commit; then
    fail=1
  fi
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "[shape] FAILED" >&2
  exit 1
fi
echo "[shape] OK" >&2
