---
depends-on: [plan-partition-schema]
type: task
---

# Scoped verify agent and draft-PR convergence gate

## Summary

Replace the full `reviewCycle` re-run after every `--fix` with one scoped `impl-critique-verify` agent that confirms each decided finding is resolved and diff-scans the fix commits for new regressions, emitting a `DECIDE_SCHEMA`-shaped result so `remaining_important` and `review_tally` stay correct. The full `reviewCycle` remains the mandatory fallback when verify fails or declines. Also add the convergence-gate machinery: compute `needsHuman = remaining_important > 0 || remaining_gaps > 0` in the fix loop and thread the flag through the workflow (consumed post-Push by `recap-phase-wiring`), plus a new `provider/git-remote/github/pr-draft.sh` that converts an already-opened PR to draft (wrapping `gh pr ready <n> --undo`) and its `provider/git-remote/contract.md` entry. `needs-human` is applied downstream as an idempotent label, never a lifecycle state, so an unconverged unit stays `in-review` (its worktree survives).

## Implementation

Chain position: this unit edits `autocode/impl/skills/impl/scripts/impl-workflow.mjs` after `plan-partition-schema` (which has already folded out the Partition phase) and before `per-module-gapcheck`. Isolated worktrees assume file-disjoint parallelism, so the single-file impl-workflow chain is why this is sequential (epic `DESIGN.md`, decision 1).

### Files to modify

`autocode/impl/skills/impl/scripts/impl-workflow.mjs`

- `meta.phases`: add a `Verify` phase entry (`model: 'opus'`) describing the scoped resolution + regression check. Do not touch the `Partition` entry (already removed by `plan-partition-schema`).
- Fix loop (currently `impl-workflow.mjs:337-348`): keep the round-0 `reviewCycle` and the `while (importantOf(decided).length && round < MAX_FIX_ROUNDS)` guard. After the `impl-execute --fix` call, replace the re-review (`decided = await reviewCycle(...)` at `:347`) with a scoped `Verify` agent call. On verify failure or low-confidence decline, fall back to the full `reviewCycle` so `decided` is always a well-formed decided object.
- Verify agent: `model: 'opus'`, `phase: 'Verify'`, `label: 'verify-r${round}'`, read-only (`readOnly` prefix, `inWt`), running the new `impl-critique-verify` skill via `follow(skill('impl-critique-verify'), ...)`. Pass it the just-applied decided findings (`importantOf(decided)` from the prior round) and the base ref `BASE` so it can compute the fix-commit diff itself. Its `schema` is the existing `DECIDE_SCHEMA` verbatim (`impl-workflow.mjs:101-124`); the verify output shape is identical (`actionable[]` keyed on `severity: 'Important'|'Nit'`, plus `dropped`, `tally`), so no new schema constant is added. `additionalProperties: false` already rejects any extra key.
- Fallback contract: the workflow treats a `null`/failed verify result, or a verify the skill declines on low confidence, as the signal to run the full `reviewCycle(...)` for that round. Because `DECIDE_SCHEMA` has no confidence field (and cannot gain one), low-confidence is signaled by the agent returning no structured object (agent() -> null), not by an added field.
- Convergence flag: after the fix loop, compute `const needsHuman = importantOf(decided).length > 0 || remainingGaps > 0` (reusing the existing `importantOf` at `:193` and `remainingGaps` at `:311,334`). Add `needs_human: needsHuman` to the returned object (`:364-373`). This is the threading point; `recap-phase-wiring` consumes it post-Push to invoke `pr-draft.sh` and apply the label. `remaining_important` (`:368`) and `review_tally` (`:369`) stay correct because `decided` is always a `DECIDE_SCHEMA` object (verify output or fallback).

`impl-critique-review`/`impl-critique-decide` and the `reviewCycle` internals are unchanged; verify sits beside them as a fourth critique leaf that does behavioral verification (the existing four are read-only diff reviewers only, research `verify-agent-skill`).

`provider/git-remote/contract.md`

- Add a `pr-draft.sh` row to the Required scripts table: args `<pr> [-g <owner/repo>]`, stdout none (side-effect only). Add a Notes entry: converts an already-opened PR to draft via `gh pr ready <pr> --undo`; idempotent (an already-draft PR is a no-op, exit `0`). Deliberately not `--draft` through `pr-create.sh`, which rejects unknown args (`pr-create.sh:37`) and whose SKILL.md `impl-recap-surface` also edits (epic `DESIGN.md`, decision 4).

### Files to create

`autocode/impl/skills/impl-critique-verify/SKILL.md` (body-only, no frontmatter)

Read-only scoped verifier. Mirrors the `impl-critique-decide` body shape (`impl-critique-decide/SKILL.md`). Contract:

- Input (caller-supplied): the decided findings applied this fix round (each `file:line`, `severity`, `claim`, `fix`) and the base ref. It computes the fix-commit diff itself.
- Workflow: (a) confirm each supplied finding is resolved in the current tree; (b) diff-scan the fix commits for NEW regressions outside the decided set; a survivor or a regression becomes an `actionable` item.
- Output: a `DECIDE_SCHEMA`-compatible object. `severity` MUST be exactly `Important` or `Nit`; `fix` MUST be populated for every `Important` survivor (it feeds `impl-execute --fix`, `impl-workflow.mjs:342-345`); `dropped` counts findings confirmed resolved; `tally` is a one-line summary. Low-confidence: decline (emit no object) so the workflow falls back to the full `reviewCycle`.
- Rules: read-only (never edit or run mutating commands); every supplied finding accounted for (resolved -> dropped, or still-open -> actionable).

`plugins/autocode/skills/impl-critique-verify/SKILL.md` (shim: frontmatter + one read line)

Frontmatter `name: impl-critique-verify` (globally unique, research `verify-agent-skill`), a `description` with a "Use when..." trigger, and a body line reading `@~/.autocode/autocode/impl/skills/impl-critique-verify/SKILL.md` with `$ARGUMENTS` forwarded, matching the `impl-critique-decide` shim.

`provider/git-remote/github/pr-draft.sh`

`#!/usr/bin/env bash` + `set -euo pipefail`; `gh` presence check (exit `2`) matching `pr-status.sh:8-11`. Usage `pr-draft.sh <pr> [-g <owner/repo>]`, arg parsing mirroring `pr-status.sh:17-42` (`-g` -> `--repo`). Runs `gh pr ready <pr> --undo` (converts open -> draft). Side-effect only, no stdout. Idempotent: tolerate an already-draft PR (swallow the "already draft" error, exit `0`). The `needs-human` label is NOT applied here (that is the consumer's inline `gh label create needs-human --force >/dev/null 2>&1 || true` + `--add-label`, pattern from `issue-transition.sh:56`); this script only toggles draft state.

```
fix loop (per round, after impl-execute --fix)
  decided(prev) --applied--> Verify (opus, scoped)
                               |  confirm resolved + diff-scan regressions
                               v
                     decided(DECIDE_SCHEMA)  --ok-->  loop guard
                               |
                            null/decline
                               v
                     reviewCycle (full, mandatory fallback) --> decided
after loop: needsHuman = remaining_important>0 || remaining_gaps>0  (threaded out)
```

### Tests that prove it

Workflow scripts have no unit harness; verify by driving the flow (epic `DESIGN.md` testing strategy).

- Run the impl workflow on a small unit with one seeded `Important` finding; confirm the emitted phase list shows a single `Verify` (opus) after the `--fix`, not the full `Prep/Review/Challenge/Decide` cascade, and that `remaining_important`/`review_tally` in the return stay correct.
- Force a verify failure (skill unavailable / declined) and confirm the full `reviewCycle` fallback runs for that round and `decided` remains well-formed.
- Confirm the return carries `needs_human: true` when `remaining_important > 0` or `remaining_gaps > 0`, else `false`.
- `pr-draft.sh`: against a real open PR, run once -> `gh pr view --json isDraft` is `true`; run twice -> still draft, exit `0`. `shellcheck provider/git-remote/github/pr-draft.sh` passes.
- `scripts/check-plugin-shape.sh` passes for the new `impl-critique-verify` skill (body-only real file, frontmatter shim).
</content>
</invoke>
