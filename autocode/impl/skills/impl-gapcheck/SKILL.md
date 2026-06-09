# Impl gapcheck

Read-only spec-completeness pass. The caller supplies the plan and the branch diff; for each in-scope plan item, verify the diff implements it; return a coverage verdict. Distinct from `impl-critique`: gapcheck answers "is every plan item present", not "is the code correct/secure/fast". Never edit, write, or run mutating commands.

## Input

Always supplied by the caller (you do not fish for files):
- The implementation plan at `.autocode/.impl-plan.md`.
- The branch diff (committed + uncommitted) or the changed-file list.

The skill does not redesign or re-plan; it only checks coverage of the supplied plan against the supplied diff.

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
