# Auto-archive completed design epics

## Summary

When a design epic's last unit PR merges, nothing archives the design folder: it stays under `.autocode/design/`, the epic issue stays open, and the `INDEX.md` row stays `active`. `design-folder.md` promises "`impl-archive` (manual) or the GH Action moves it," but no archive GH Action ships and `/impl-archive` is invoked entirely by hand, so completed epics silently rot (three flat epics in a downstream repo stuck `active` with closed issues). This epic closes the gap two ways: `/impl` detects a fully-merged epic on its next run and hands off to `/impl-archive`, and a new pure-bash `autocode-archive-design` GitHub Action archives by `design_id` on `workflow_dispatch`. Both open one archive PR that moves the folder, flips the INDEX row, and (multi-unit only) carries `Closes #<epic>` so merging the PR closes the epic. `/impl-archive` drops its current direct `issue-transition` close to match.

## Background

The fan-out half of the lifecycle is automated (a merged design PR creates issues via the `autocreate-design-doc-issue` Action); the archive half is not. The pieces today:

| Component | File | Current behavior |
|---|---|---|
| Lifecycle spec | `autocode/design/design-folder.md` | "Epic done = folder under `.autocode/archive/`; `impl-archive` or the GH Action moves it." The Action does not exist. |
| Manual archive | `autocode/impl/skills/impl-archive/SKILL.md` | Verifies units done, closes the epic via `issue-transition <epic> done` directly (step 4), then opens a lightweight folder-move PR. Epic closes before the PR merges. |
| Unit launcher | `autocode/impl/skills/impl/SKILL.md` | Thin launcher: `impl-start` picks a unit, a background workflow drives it to a PR. Ends at PR open; never revisits epic completion. |
| Unit selection | `autocode/impl/skills/impl-start/SKILL.md` | Step 4: a unit is ready iff `todo` and deps `done`. "If the ready set is empty, report why (all done, or blocked) and stop." All-done and blocked collapse to one dead end. |
| Fan-out Action | `plugins/autocode/templates/autocreate-design-doc-issue/` | Pure-bash composite action + workflow; matches `autocode:epic`/`autocode:unit` markers via `gh api issues?state=all` + GraphQL `sub_issues`. The shape the archive Action mirrors. |

A unit's sub-issue becomes `done` only when its PR merges, but `/impl` ends at PR open. So at the end of an `impl` run the just-pushed unit is `in-review`, not `done`: epic completeness can only be read on a later run, after that merge. That timing is why detection lives at `impl`'s entry (a subsequent run), not at its exit.

## Architecture

Two triggers, one archive behavior. The archive behavior already lives in `/impl-archive` (the manual/AI path); the new Action is its no-AI counterpart, the same skill/Action duality as `design-fanout`/`autocreate-design-doc-issue`. Neither trigger fires unattended on every merge.

```
last unit PR merges  ──>  epic's units all `done` (closed)
        │
        ├─ user runs `/impl --from-design <id>` again
        │     └─ impl-start discovery: ready set empty AND all units done
        │           └─ outcome = epic_complete  ──>  /impl hands off to /impl-archive <id>
        │
        └─ user dispatches autocode-archive-design (workflow_dispatch, input design_id=<id>)
              └─ pure-bash: verify all units closed
                                  │
        both paths converge ──────┘
              ▼
        branch chore/archive-<id>-<short>
        git mv .autocode/design/<id>-<short>  ->  .autocode/archive/<id>-<short>
        flip INDEX.md row: active -> archived
        open PR  (multi-unit: body `Closes #<epic>`; flat: no Closes)
              ▼
        PR merges  ->  folder archived + epic issue closed (multi-unit)
```

Detection contract (both paths read the same source): `issue-epic-list --epic <id>` / `gh api issues?state=all` + GraphQL `sub_issues`, matched on the `<!-- autocode:epic=<id> -->` and `<!-- autocode:unit=<id>/<slug> -->` body markers. Flat design = the single epic-marked issue is also the unit; multi-unit = every sub-issue must be closed.

## Design decisions

1. **Detection at `/impl`'s entry, not its exit.** A unit is `done` only after its PR merges; `/impl` exits at PR open. Checking completeness when `impl-start` discovery runs (a later invocation) reads true merged state. Rejected: archiving inside the same run that pushed the last unit (the unit isn't merged yet, so "last unit done" is unknowable there).

2. **Trigger is user-gated, never an on-merge sweep.** `/impl` hand-off requires the user to run `/impl`; the Action requires an explicit `workflow_dispatch` with `design_id`. Rejected: a `pull_request: closed` sweep of active epics. It only opens PRs (nothing destructive), but firing on every merge across all active epics is uncontrolled and noisy; an explicit by-id trigger is predictable.

3. **Epic closes via the archive PR's `Closes #<epic>`, not a direct transition.** `/impl-archive` today closes the epic before its folder-move PR merges, so an abandoned PR leaves a closed epic with an un-archived folder. Tying the close to the merge (a `Closes #<epic>` link) unifies the manual skill with the Action: both just open a PR. The two layers produce that link the way each layer should. The Action uses `gh` directly (like the fan-out Action), so it hand-writes `Closes #<epic>` in the PR body. `/impl-archive` goes through `pr-create`, where the close line is owned by `pr-issue-link.sh` and never hand-written; so the skill calls `pr-create --issue <epic-key>` WITHOUT `--lightweight` (adding `--no-review --no-pr-hygiene` to keep a mechanical move clean), letting the provider append the canonical `Closes #<ref>`. `--lightweight` would skip that linking, which is why the current flat-only `--lightweight` path cannot carry it. Flat designs have no epic issue, so they keep `--lightweight` and no `Closes`; their single issue was already closed by its own unit PR.

4. **The Action is pure bash, mirroring the fan-out Action.** Archiving is mechanical (folder move, INDEX edit, marker-matched completeness check): no model needed. Reusing the fan-out Action's composite-action + workflow shape, its `gh api` marker queries, and the default `GITHUB_TOKEN` keeps it reliable and dependency-free. The skill remains the AI/interactive path; the Action is the CI path.

5. **`impl-start` reports `epic_complete` vs `waiting` distinctly.** Step 4's single "ready set empty" dead end can't tell `/impl` whether to archive (all done) or wait (remaining units `in-review`/blocked). Splitting the outcome lets `/impl` hand off only when truly complete, and gives a useful nudge in both cases.

## Runtime flow

1. Last unit PR merges; the tracker auto-closes its sub-issue via `Closes #<unit>`. Every unit of the epic is now `done`.
2. The user runs `/impl --from-design <id>` (intending the next unit). `impl-start` discovery maps markers, computes the ready set: empty. It checks the non-ready units: all `done` -> outcome `epic_complete` (vs some `in-review`/blocked -> `waiting`).
3. On `epic_complete`, `impl-start` reports "epic complete" with the nudge, and `/impl` hands off to `/impl-archive <id>` instead of launching the unit workflow.
4. `/impl-archive` (or, on the Action path, the dispatched workflow) verifies completeness from the discovery call, ensures a worktree + `chore/archive-<id>-<short>` branch, `git mv`s the folder to `.autocode/archive/`, flips the INDEX row to `archived`, and opens a PR. Multi-unit: body carries `Closes #<epic>`. Flat: no `Closes`.
5. Merging the archive PR moves the folder on the default branch and (multi-unit) closes the epic issue via the `Closes` link. The lifecycle invariant holds: folder under `.autocode/archive/` is the epic-level source of truth for done.

## Edge cases and error handling

- **Idempotent re-run.** Both paths skip cleanly if the INDEX row is already `archived` or the source folder is already under `.autocode/archive/` (the move already happened). They also skip in-flight: if the archive branch `chore/archive-<id>-<short>` or its PR already exists (one path opened a PR the other now races), report and stop without recreating the branch or opening a duplicate. The skill and the Action share this idempotency identically. `issue-epic-list` on an already-closed epic is tolerated.
- **Incomplete epic.** If any unit is not closed, the Action exits reporting the outstanding units (slug + status) and `/impl-archive` stops; never archive a partially-done epic.
- **Not fanned out.** `issue-epic-list --epic <id>` returns `[]` (design PR not merged / no issues). Report and stop; nothing to archive.
- **Flat design.** No `units/` dir, no separate epic issue: completeness = the single epic-marked issue is closed; archive PR has no `Closes`.
- **`waiting` outcome.** Remaining units `in-review` or blocked on unfinished deps: `/impl` does not archive and does not error; it reports what's outstanding (matching today's "blocked" report).
- **Action token.** The default `GITHUB_TOKEN` needs `contents: write` (branch + commit + push), `pull-requests: write` (open PR), `issues: read` (read issue/sub-issue state). No extra secrets.
- **`design_id` input.** A `design_id` with no matching `.autocode/design/<id>-*` folder (e.g. already archived, or typo): the Action reports and exits non-fatally.

## Testing strategy

- **Action script (pure bash):** unit-test the archive script against fixture design folders (flat and multi-unit) and a faked `gh` (stubbed `issues?state=all` + `sub_issues` responses) for: all-closed -> archive; one-open -> abort with outstanding list; already-archived -> idempotent skip; flat -> no `Closes`; multi -> `Closes #<epic>`. Assert the `git mv`, the INDEX flip, and the rendered PR body. Mirror the fan-out template's existing test conventions where present.
- **Skill changes:** no automated harness for skill bodies; verify by reading the updated `impl-start` outcome split and `/impl-archive` PR-body change, and dry-run `/impl --from-design <id>` against an epic whose units are all closed (hand-off fires) vs one with an `in-review` unit (`waiting`).
- **Shape + CI:** `scripts/check-plugin-shape.sh` must stay green (the template is outside its scope; confirm). `**/*.sh` rule glob already covers the new script.

## Sources

- `autocode/design/design-folder.md` lifecycle section ("`impl-archive` (manual) or the GH Action moves it"; epic-done = folder under `.autocode/archive/`); INDEX.md registry semantics. The gap and the invariant.
- `autocode/impl/skills/impl-archive/SKILL.md` steps 4-7: current direct `issue-transition <epic> done` then lightweight PR. The behavior being unified.
- `autocode/impl/skills/impl/SKILL.md`: thin launcher, ends at PR open. Where the hand-off attaches.
- `autocode/impl/skills/impl-start/SKILL.md` step 4: "ready set empty -> report why and stop." The outcome to split.
- `autocode/impl/skills/impl/scripts/impl-workflow.mjs`: workflow ends at Push/Hygiene (PR open), confirming a unit is `in-review` not `done` at run end.
- `plugins/autocode/templates/autocreate-design-doc-issue/.github/workflows/autocreate-design-doc-issue.yml` and `.github/actions/design-fanout/{action.yml,render-design-issues.sh}`: composite-action + workflow shape, marker-matched `gh api issues?state=all` + GraphQL `sub_issues` queries, default-`GITHUB_TOKEN` permission model. The pattern the archive Action mirrors.
- `autocode/pr/skills/pr-create/SKILL.md` step 6 + Rules: the close line is owned by `pr-issue-link.sh` (never hand-written), and `--lightweight` skips linking. Why the skill path uses `--issue` without `--lightweight` while the Action hand-writes `Closes`.
- `plugins/autocode/skills/autocode-setup/SKILL.md` Step 6: optional-Action install (copy template into repo `.github/`). Where the new template's install attaches.
- `scripts/check-plugin-shape.sh` (no `templates/` handling) and `.claude/rules/shell-scripts-conventions.md` (`paths: **/*.sh`): the template is outside shape-check scope; its script is covered by the shell rule. Verified by direct read.
- Handover trace (`autocode-handover` 2026-06-04): three flat epics (`0001`/`0002`/`0003`) in `backend.ai-lagrange` stuck `active` despite closed issues; `.autocode/archive/` never created. The motivating failure.

## Units

| unit | deliverable | depends-on |
|---|---|---|
| [archive-action-template](units/archive-action-template.md) | New pure-bash `autocode-archive-design` GH Action template (workflow_dispatch by `design_id` + composite action + archive script) | |
| [impl-archive-closes-epic](units/impl-archive-closes-epic.md) | `/impl-archive` drops the direct `issue-transition`; archive PR carries `Closes #<epic>` (multi-unit only) | |
| [impl-completion-handoff](units/impl-completion-handoff.md) | `impl-start` splits `epic_complete` vs `waiting`; `/impl` hands off to `/impl-archive`; nudge text | impl-archive-closes-epic |
| [lifecycle-and-setup-wiring](units/lifecycle-and-setup-wiring.md) | `design-folder.md` lifecycle update + `autocode-setup` Step 6 installs the new template | archive-action-template |

## Critique log

### Iteration 1

- Q: pr-create `--issue <epic-key> --no-review --no-pr-hygiene` without `--lightweight`: does that combo actually link `Closes #<epic>`? R: Verified (source read). `--lightweight` skips linking (step 6); the three concerns (link, reviewers, hygiene) are independent flags; `--issue` without `--lightweight` runs linking, `--no-review`/`--no-pr-hygiene` skip the rest. Design mechanism stands, no change.
- Q: Does the `--auto` result block emit the keys the design says not to break (incl. `epic_key`)? R: Verified (impl-start step 10): emits worktree path, branch, slug, unit_key, epic_key, design_id; `epic_key` empty for flat. `shortname` lives in `.impl-context` but not the result block, so adding it is additive. No change.
- Q: Fan-out queries / INDEX format / CI assumptions accurate? R: Verified. Epic query `gh api --paginate /repos/$REPO/issues?state=all` + `select(.pull_request | not)`; sub_issues via `-H GraphQL-Features:sub_issues` then REST `/issues/<n>/sub_issues`; CI runs only `check-plugin-shape.sh` + shellcheck; no test harness exists. No change.
- Q: Skill path idempotency only covers post-merge (folder moved / INDEX archived); an in-flight archive PR from the Action plus an `/impl` hand-off would race on the existing branch. R: (user) Mirror the Action's branch/PR-exists idempotency in `/impl-archive`. Applied to `units/impl-archive-closes-epic.md` Rules and DESIGN edge case.
- Q: Units describe INDEX status as `status: archived` (frontmatter), but it is a Markdown table column; the flip needs a row-targeted spec. R: (user) Specify row-targeted column edit: match by `<id>` in column 1, replace only that row's status cell `active` -> `archived`, never global. Applied to `units/archive-action-template.md` (steps 2, 5) and `units/impl-archive-closes-epic.md`.
