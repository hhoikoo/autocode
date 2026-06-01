# Impl start

Set up a worktree + feature branch for one unit of work. From a design epic, this picks a single DAG-ready unit; it also supports a bare ticket or a freeform description.

Design-epic discovery, markers, the DAG, and the lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

One of:
- `--from-design <id | shortname>`: pick a ready unit from a fanned-out design epic.
- `<ticket-id>` (e.g. `42`, `BA-1234`): ticket mode.
- `<type>: <description>` (e.g. `feat: add login flow`): description mode.

## Workflow (from-design)

1. Locate `.autocode/design/<id>-<short>/` (glob on either half). Read `DESIGN.md` and any `units/*.md`. Multi-unit if `units/` exists; flat otherwise.
2. Discover issues: `provider/run.sh issue-tracker issue-list --label "autocode-epic:<id>" --state all`. If it returns `[]`, the design has not been fanned out; tell the user to run `/design-fanout <id>` (or wait for the Action) and stop.
3. Map markers to issues. For each returned issue, read its `description` for a marker:
   - `<!-- autocode:epic=<id> -->` -> the epic issue (also the single unit in a flat design).
   - `<!-- autocode:unit=<id>/<slug> -->` -> that unit's sub-issue.
   Record each unit's `{slug, key, status}`.
4. Compute the ready set:
   - Flat design: the one issue is the unit; ready iff its status is `todo`.
   - Multi-unit: a unit is ready iff its status is `todo` and every slug in its `depends-on` (from the unit file frontmatter) maps to a unit whose status is `done`. Units already `in-progress`/`in-review`/`done` are excluded.
   - If the ready set is empty, report why (all done, or all remaining are blocked on unfinished deps) and stop.
5. Present the ready units via `AskUserQuestion` (slug + one-line deliverable). The user picks one. Its sub-issue `key` is the ticket for the rest of the flow.
6. Use `EnterWorktree` to create a worktree based on the repo's default branch (deps are already merged there). Inside it, delegate to `git-create-branch <key>` for the feature branch.
7. Transition state:
   - `provider/run.sh issue-tracker issue-transition <key> in-progress`.
   - Multi-unit: if the epic issue status is still `todo`, `provider/run.sh issue-tracker issue-transition <epic-key> in-progress`.
8. Seed the per-unit log. In the worktree, create `.autocode/design/<id>-<short>/progress/<slug>.md` with the header from the design-folder spec (slug, epic, branch, started date). Multi-unit only writes under the existing folder; flat uses slug `<short>`.
9. Seed the worktree state files (both gitignored; the Stop progress hook reads them):
   - `.autocode/.impl-context`: a JSON object with keys `design_id`, `shortname`, `slug`, `unit_key`, `epic_key` (empty string for flat), `progress_log` (absolute path to the per-unit log). The hook parses this with `jq`, so it must be valid JSON.
   - `.autocode/.progress-last-sha`: current `git rev-parse HEAD`.
10. Report: worktree path, branch, unit slug, sub-issue key, and next step (implement, then `/impl-push`).

## Workflow (ticket / description mode)

1. Treat the arg as a ticket id (ticket mode) or `<type>: <description>` (description mode). No design epic, no unit selection, no progress log.
2. `EnterWorktree` based on the default branch; inside it, delegate to `git-create-branch`.
3. Report worktree path, branch, ticket id (if any), and next step.

## Rules

- Worktree base is the repo's default branch. Units merge to the default branch directly; there is no epic integration branch. A unit's dependencies being `done` (closed) means their code is already on the default branch the worktree is based on.
- Never branch from a dirty working tree on the default branch.
- Delegate branch creation to `git-create-branch`; never duplicate that logic.
- Pick exactly one ready unit per invocation. Re-run the skill to start another.
- The state files (`.autocode/.impl-context`, `.autocode/.progress-last-sha`) are gitignored; ensure `$repo_root/.autocode/.gitignore` ignores them (create if missing).

$ARGUMENTS
