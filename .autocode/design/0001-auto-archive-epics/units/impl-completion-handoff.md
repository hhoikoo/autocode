---
depends-on: [impl-archive-closes-epic]
type: task
---

# Hand off a completed epic from /impl to /impl-archive

## Summary

Today `impl-start` step 4 collapses two unlike dead ends into one "ready set empty" report: an epic with every unit `done` (archivable) and an epic still waiting on `in-review`/blocked units (not archivable). And `/impl` never revisits epic completion, so a fully-merged epic is never archived without a hand-run of `/impl-archive`. This unit splits that dead end into two machine-readable outcomes, `epic_complete` vs `waiting`, surfaces them in `impl-start`'s human report and its `--auto` result block, and adds one control-flow branch to `/impl`: on `epic_complete`, hand off to `/impl-archive <id>` instead of launching the unit workflow. Detection lands on a subsequent `/impl` run, because a unit is `done` only after its PR merges and `/impl` exits at PR open, so the run that pushed the last unit cannot see it merged. `/impl` stays a thin launcher; archiving stays `/impl-archive`'s job.

## Implementation

Modify two canonical body-only skill sources (not the plugin shims):

- `autocode/impl/skills/impl-start/SKILL.md`
- `autocode/impl/skills/impl/SKILL.md`

Read both current skills, plus `autocode/design/design-folder.md` (lifecycle, ready-set rule, discovery, the `--auto` result-block contract). Read `autocode/impl/skills/impl/scripts/impl-workflow.mjs` only if needed to confirm the workflow ends at Push/Hygiene (PR open); it does, so the hand-off attaches in the SKILL launcher, not the `.mjs`.

### impl-start changes (step 4 + step 10)

In step 4 (ready set empty case), split the single dead end into two outcomes computed from the per-unit `{slug, status}` map already built in step 3:

- `epic_complete`: ready set empty AND every unit's status is `done`. Flat design: the single epic-marked issue is `done` (closed).
- `waiting`: ready set empty AND at least one unit is not `done` (any of `in-progress`, `in-review`, or `todo` blocked on an unfinished dep).

Reporting:

- Interactive `epic_complete`: a clear "epic complete" message carrying the nudge: `Epic <id>-<short> complete. Archive it: /impl-archive <id> (or dispatch the autocode-archive-design workflow with design_id=<id>).`
- Interactive `waiting`: report the outstanding units (slug + status), as today's "blocked/all-remaining" report does.

Under `--auto` (step 10), extend the existing structured result block with one field that lets the caller branch. Do not break the current keys (worktree path, branch, slug, unit_key, epic_key, design_id). Add:

```
outcome: ready | epic_complete | waiting
```

- `ready`: a unit was selected; emit the unit-selection fields as today.
- `epic_complete` / `waiting`: omit the unit-selection fields (slug, unit_key, worktree); include `design_id` and `shortname` so the caller can route. For `waiting`, also include the outstanding units (slug + status).

`impl-start` only detects and reports/returns the outcome. It does not archive.

### impl changes (step 1 + Workflow/Rules prose)

After step 1 delegates to `impl-start`, capture the `outcome` (alongside the existing worktree path, `slug`, `unit_key`, `design_id`) and route on it. This is the only added control-flow branch:

- `ready`: proceed as today; resolve workflow inputs (step 2) and launch the background workflow (step 3).
- `epic_complete`: do NOT launch the unit workflow. Hand off to `/impl-archive <id>` using the `design_id` from `impl-start`. Archiving (folder move, INDEX flip, epic close) is `/impl-archive`'s job; do not inline it. This hand-off to the target's behavior is why this unit depends on `impl-archive-closes-epic`.
- `waiting`: report the outstanding units and stop. No archive, no error.

Update step 1's prose to capture `outcome`, and the Workflow/Rules sections to state the three-way route while keeping `/impl` a thin launcher (it routes; it does not implement archive logic).

### Edge cases

- Flat design: the single issue `done` -> `epic_complete`. Hand-off still runs `/impl-archive <id>`, which for a flat design moves the folder and flips the INDEX row only (no separate epic issue to close).
- The three stuck flat epics in the downstream repo become archivable by re-running `/impl --from-design <id>`: the single issue is closed -> `epic_complete` -> hand-off.

### Verification

No automated harness for skill bodies. Dry-run `/impl --from-design <id>` against:

- (a) an epic with all units closed -> hand-off to `/impl-archive` fires;
- (b) an epic with one unit `in-review` -> `waiting`, no archive;
- (c) an epic with a ready unit -> normal workflow launch.
