---
depends-on: []
type: task
---

# Read-only impl-gapcheck leaf skill

## Summary

A new read-only leaf skill `impl-gapcheck` that checks whether every item in the implementation plan was actually implemented in the branch diff, returning a spec-completeness verdict. The caller (the `impl` workflow) supplies the plan (`.autocode/.impl-plan.md`) and the branch diff; for each in-scope plan item (per-file task and each module in the plan's `## Module partition`) the skill verifies the diff implements it, treating a missing or empty implementation as a gap and skipping items the plan marked out-of-scope. It returns `{ complete, gaps[] }` where `complete` is true only when every in-scope item is present. This is a spec-coverage check, distinct from `impl-critique` (which answers "is the code correct/secure/fast"): gapcheck answers only "is every plan item present". It is read-only and never edits, writes, or runs mutating commands. The deliverable is the real body-only skill file, its plugin shim, and a CLAUDE.md entry; the workflow wiring and the JSON schema live in the sibling `workflow-fanout-wiring` unit.

## Implementation

Per epic Design decision 6: gapcheck is a new leaf, not a dimension of `impl-critique` (different question, different prompt, different schema `{ complete, gaps[] }`); it is read-only and run by the workflow exactly like the `impl-critique-*` leaves. Model the body on the existing read-only leaves `impl-critique-{review,challenge,decide}`, whose structure is `## Input` -> `## Workflow` -> `## Output` -> `## Rules`, all body-only with no frontmatter (`autocode/impl/skills/impl-critique-review/SKILL.md:1-40`).

Files to create:

- `autocode/impl/skills/impl-gapcheck/SKILL.md` (real, body-only). Must NOT start with `---`; `scripts/check-plugin-shape.sh` rejects real files that open with a frontmatter block, requires exactly one real counterpart per shim, and requires `impl-gapcheck` to be a name unique across all feature-sets.
- `plugins/autocode/skills/impl-gapcheck/SKILL.md` (shim). Copy the shape of `plugins/autocode/skills/impl-critique-review/SKILL.md:1-6`: frontmatter with ONLY `name:` and `description:` (no `model`, no `allowed-tools`), then one body line:
  `Read through @~/.autocode/autocode/impl/skills/impl-gapcheck/SKILL.md and execute actions according to the instructions in the file. ` followed by `` `$ARGUMENTS` is forwarded. ``

File to modify:

- `autocode/impl/CLAUDE.md`. Lines 20-25 enumerate the `impl-critique-*` leaves (the report-only review front end). Add an entry describing `impl-gapcheck` as the read-only spec-completeness pass, distinct from the `impl-critique` quality leaves: `impl-critique` asks "is this code correct", gapcheck asks "is every plan item present". Do NOT touch the per-phase skill list at lines 13-18 (gapcheck is a leaf run by the workflow, not an individually-sequenced per-phase skill).

Skill body shape (the four sections, modeled on `impl-critique-review/SKILL.md`):

- `## Input` (caller always supplies these; the skill does not fish for files, matching `impl-critique-review/SKILL.md:5-9`): the plan at `.autocode/.impl-plan.md`, and the branch diff (or the changed-file list). The skill does not redesign or re-plan; it only checks coverage of the supplied plan against the supplied diff.
- `## Workflow`: enumerate the in-scope plan items, where an item is a per-file task in the plan plus each module listed under the plan's `## Module partition` section (the section the sibling `plan-module-partition` unit adds to `impl-plan`). For each item verify the diff actually implements it; a missing or empty implementation is a gap. Skip any item the plan marked out-of-scope (`impl-plan/SKILL.md:33` writes an out-of-scope list).
- `## Output`: the verdict object. `complete` is true only when every in-scope plan item is present in the diff; otherwise list each gap citing the plan item and the file with a one-line detail of what is missing. The format must match the schema the sibling `workflow-fanout-wiring` unit defines and consumes:
  `GAPCHECK_SCHEMA = { complete: boolean, gaps: [{ file, plan_item, detail }] }`.
  Each gap line carries a `file`, the `plan_item` it traces to, and a one-line `detail`. Return `complete: true` with an empty `gaps` list when coverage is full. (The schema itself is defined in the workflow unit, not here; this file only fixes the output shape to align with it.)
- `## Rules`: read-only (no edits, no writes, no mutating commands), per Design decision 6 and matching `impl-critique-review/SKILL.md:37-40`. Every gap cites a concrete `file` and `plan_item`; no citation, no gap. Coverage only: do not stray into correctness/quality findings (that is `impl-critique`).

What proves it (per epic Testing strategy, lines 99-104): `scripts/check-plugin-shape.sh` passes for the new skill + shim (real file body-only, unique name, shim = frontmatter + read line). CI path globs in `.github/workflows/ci.yml` cover the new skill directory. The skill is prompt-only, not unit-testable in isolation; live verification is via the gapcheck loop firing in a heavy-unit run, owned by the `workflow-fanout-wiring` unit.

Boundary with the sibling unit:

```
gapcheck-leaf-skill (this unit)        workflow-fanout-wiring (sibling)
  impl-gapcheck/SKILL.md  ----run by---->  skill()/follow() call in
  (Input/Workflow/Output/Rules)            impl-workflow.mjs
  Output shape: {complete, gaps[]}  ===  GAPCHECK_SCHEMA (defined there)
```

This unit owns the skill body, shim, and CLAUDE.md entry only. The `skill()` call, the schema constant, and the bounded fix loop (`GAP_MAX_ROUNDS`) are the sibling unit's; this file keeps the Output format aligned with `GAPCHECK_SCHEMA` but does not implement the wiring.
