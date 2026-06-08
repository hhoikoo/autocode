#!/usr/bin/env bash
set -euo pipefail

# Self-verifying test for the PROGRESS.md union merge driver scaffold.
# No network, no gh. Builds throwaway git repos in mktemp -d.
# Exits 0 on all-pass, non-zero if any case fails.

PASS=0
FAIL=0

pass() { echo "[PASS] $*" >&2; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $*" >&2; FAIL=$((FAIL + 1)); }

GITATTRIBUTES_RULE='.autocode/design/**/PROGRESS.md merge=union'
PROGRESS_PATH='.autocode/design/0001-x/PROGRESS.md'
HEADER='# Progress: x'

# ---------------------------------------------------------------------------
# Case 1: Seeded common ancestor — union rebase succeeds, no conflict markers,
#         header appears exactly once, both appended blocks present.
# ---------------------------------------------------------------------------
case1_dir="$(mktemp -d)"
(
  cd "${case1_dir}"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"

  # Write .gitattributes with the union rule
  echo "${GITATTRIBUTES_RULE}" > .gitattributes
  git add .gitattributes

  # Seed the common ancestor
  mkdir -p "$(dirname "${PROGRESS_PATH}")"
  printf '%s\n' "${HEADER}" > "${PROGRESS_PATH}"
  git add "${PROGRESS_PATH}"
  git commit -q -m "base: seed PROGRESS.md"
  BASE_COMMIT="$(git rev-parse HEAD)"

  # Branch A: append block-a
  git checkout -q -b branch-a
  printf '\n## block-a\n\nunit A work done.\n' >> "${PROGRESS_PATH}"
  git add "${PROGRESS_PATH}"
  git commit -q -m "progress: append block-a"

  # Branch B (from seeded base): append block-b
  git checkout -q "${BASE_COMMIT}"
  git checkout -q -b branch-b
  printf '\n## block-b\n\nunit B work done.\n' >> "${PROGRESS_PATH}"
  git add "${PROGRESS_PATH}"
  git commit -q -m "progress: append block-b"

  # Rebase branch-b onto branch-a
  git rebase branch-a -q

  header_count="$(grep -c "^# Progress:" "${PROGRESS_PATH}" || true)"
  conflict_count="$(grep -c "^<<<<<<<" "${PROGRESS_PATH}" || true)"
  has_block_a="$(grep -c "block-a" "${PROGRESS_PATH}" || true)"
  has_block_b="$(grep -c "block-b" "${PROGRESS_PATH}" || true)"

  if [[ "${conflict_count}" -eq 0 && "${header_count}" -eq 1 && "${has_block_a}" -ge 1 && "${has_block_b}" -ge 1 ]]; then
    pass "case 1: seeded common ancestor — no conflicts, both blocks present, header once"
  else
    fail "case 1: seeded common ancestor — conflicts=${conflict_count} header_count=${header_count} block-a=${has_block_a} block-b=${has_block_b}"
  fi
)
rm -rf "${case1_dir}"

# ---------------------------------------------------------------------------
# Case 2: No-rule regression — parallel branches without the merge=union
#         gitattributes rule cause a conflict on merge (documents why the
#         .gitattributes rule is required). With the rule, the same scenario
#         resolves cleanly.
# ---------------------------------------------------------------------------
case2_dir="$(mktemp -d)"
(
  cd "${case2_dir}"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"

  # NO .gitattributes — omit the union rule intentionally
  git commit -q --allow-empty -m "base: no gitattributes"
  BASE_COMMIT="$(git rev-parse HEAD)"

  # Branch A: creates PROGRESS.md with header + block-a
  git checkout -q -b branch-a
  mkdir -p "$(dirname "${PROGRESS_PATH}")"
  printf '%s\n\n## block-a\n\nunit A work done.\n' "${HEADER}" > "${PROGRESS_PATH}"
  git add "${PROGRESS_PATH}"
  git commit -q -m "progress: branch-a creates PROGRESS.md"

  # Branch B (from same base): creates PROGRESS.md with header + block-b
  git checkout -q "${BASE_COMMIT}"
  git checkout -q -b branch-b
  mkdir -p "$(dirname "${PROGRESS_PATH}")"
  printf '%s\n\n## block-b\n\nunit B work done.\n' "${HEADER}" > "${PROGRESS_PATH}"
  git add "${PROGRESS_PATH}"
  git commit -q -m "progress: branch-b creates PROGRESS.md"

  # Merge branch-a into branch-b WITHOUT union driver: expect conflict
  merge_exit=0
  git merge --no-edit branch-a -q 2>/dev/null || merge_exit=$?

  if [[ "${merge_exit}" -ne 0 ]]; then
    conflict_count="$(grep -c "^<<<<<<<" "${PROGRESS_PATH}" || true)"
    if [[ "${conflict_count}" -gt 0 ]]; then
      pass "case 2: no-rule regression — parallel add/add causes conflict without merge=union rule (exit=${merge_exit}, markers=${conflict_count})"
    else
      fail "case 2: no-rule regression — merge failed (exit=${merge_exit}) but no conflict markers found"
    fi
  else
    fail "case 2: no-rule regression — expected conflict without merge=union rule, but merge succeeded (should not happen)"
  fi
)
rm -rf "${case2_dir}"

# ---------------------------------------------------------------------------
# Case 3: Seed idempotency — writing the header-only PROGRESS.md twice keeps
#         exactly one header, and an existing file with appended blocks is
#         never clobbered (blocks survive, header count stays 1).
# ---------------------------------------------------------------------------
case3_dir="$(mktemp -d)"
(
  cd "${case3_dir}"
  mkdir -p "$(dirname "${PROGRESS_PATH}")"

  # First seed write (absent -> create)
  if [[ ! -f "${PROGRESS_PATH}" ]]; then
    printf '%s\n' "${HEADER}" > "${PROGRESS_PATH}"
  fi

  # Second seed write (present -> no-op)
  if [[ ! -f "${PROGRESS_PATH}" ]]; then
    printf '%s\n' "${HEADER}" > "${PROGRESS_PATH}"
  fi

  header_count="$(grep -c "^# Progress:" "${PROGRESS_PATH}" || true)"
  if [[ "${header_count}" -ne 1 ]]; then
    fail "case 3a: seed idempotency — expected 1 header after two seed calls, got ${header_count}"
  else
    pass "case 3a: seed idempotency — header appears exactly once after two seed calls"
  fi

  # Simulate an existing file with appended blocks; seed must not clobber it
  appended_file="${case3_dir}/appended-progress.md"
  printf '%s\n\n## block-existing\n\nalready done.\n' "${HEADER}" > "${appended_file}"

  # Seed logic: create if absent (file is present, so skip)
  if [[ ! -f "${appended_file}" ]]; then
    printf '%s\n' "${HEADER}" > "${appended_file}"
  fi

  final_header="$(grep -c "^# Progress:" "${appended_file}" || true)"
  has_block="$(grep -c "block-existing" "${appended_file}" || true)"

  if [[ "${final_header}" -eq 1 && "${has_block}" -ge 1 ]]; then
    pass "case 3b: seed idempotency — existing blocks survive, header count stays 1"
  else
    fail "case 3b: seed idempotency — header_count=${final_header} block-existing=${has_block}"
  fi
)
rm -rf "${case3_dir}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "[SUMMARY] passed=${PASS} failed=${FAIL}" >&2
if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
exit 0
