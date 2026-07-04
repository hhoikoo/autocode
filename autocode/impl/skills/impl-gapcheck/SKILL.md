# Impl gapcheck

Read-only spec-completeness pass. The caller supplies the plan path and base ref; you compute the branch diff yourself, and for each in-scope plan item verify the diff implements it, then return a coverage verdict. Distinct from `impl-critique`: gapcheck answers "is every plan item present", not "is the code correct/secure/fast". Never edit, write, or run mutating commands.

## Input

The caller supplies the plan path (`.autocode/.impl-plan.md`) and the base ref; do not fish for the plan. Compute the diff yourself with read-only git commands: `git diff <base>...HEAD`, `git diff HEAD`, and untracked files from `git status --porcelain`.

The skill does not redesign or re-plan; it only checks coverage of the supplied plan against the diff it computes.

## Workflow

Enumerate the in-scope plan items. An item is: (a) each per-file task in the plan, plus (b) each module listed under the plan's `## Module partition` section.

Skip any item the plan marked out-of-scope (the plan carries an out-of-scope list).

For each in-scope item, verify the diff actually implements it. A missing or empty implementation (no corresponding change, or a stub/empty body where the plan required real work) is a gap.

Coverage only: do not evaluate correctness, security, or performance. That is `impl-critique`'s job.

## Output

The verdict object, shape fixed to align with `GAPCHECK_SCHEMA = { complete: boolean, gaps: [{ file, plan_item, detail }] }`:
- `complete` is `true` only when every in-scope plan item is present in the diff.
- When gaps remain, list each gap with a `file`, the `plan_item` it traces to, and a one-line `detail` of what is missing.
- Return `complete: true` with an empty `gaps` list when coverage is full.

The schema itself is defined and consumed by the workflow unit, not here; this file only fixes the output shape to match.

## Rules

- Read-only: no edits, no writes, no mutating commands.
- Every gap cites a concrete `file` and `plan_item`; no citation, no gap.
- Coverage only: do not stray into correctness/quality findings (that is `impl-critique`).
