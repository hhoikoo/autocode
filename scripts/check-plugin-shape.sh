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

# 3. Every autocode/<feature-set>/ has a CLAUDE.md
note "checking feature-set CLAUDE.md files"
for dir in autocode/*/; do
  if [[ ! -f "${dir}CLAUDE.md" ]]; then
    err "missing ${dir}CLAUDE.md"
  fi
done

# 4. Shellcheck all shell scripts under tracked locations.
note "shellchecking shell scripts"
scripts=()
while IFS= read -r f; do
  scripts+=("${f}")
done < <(find provider plugins/autocode .githooks scripts -type f -name '*.sh' 2>/dev/null | sort)

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
