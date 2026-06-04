# Impl start

Set up a worktree + feature branch for one unit of work. From a design epic, this picks a single DAG-ready unit; it also supports a bare ticket or a freeform description.

Design-epic discovery, markers, the DAG, and the lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

One of:
- `--from-design <id | shortname>`: pick a ready unit from a fanned-out design epic.
- `<ticket-id>` (e.g. `42`, `BA-1234`): ticket mode.
- `<type>: <description>` (e.g. `feat: add login flow`): description mode.

Modifiers (from-design):
- `--unit <slug>`: select this ready unit directly instead of prompting.
- `--auto`: run unattended (no `AskUserQuestion`) and end with a structured result. Requires an unambiguous unit: either `--unit`, or exactly one ready unit.

## Workflow (from-design)

1. Locate `.autocode/design/<id>-<short>/` (glob on either half). Read `DESIGN.md` and any `units/*.md`. Multi-unit if `units/` exists; flat otherwise.
2. Discover issues: `provider/run.sh issue-tracker issue-epic-list --epic <id>`. If it returns `[]`, the design has not been fanned out; tell the user to run `/design-fanout <id>` (or wait for the Action) and stop.
3. Map markers to issues. For each returned issue, read its `description` for a marker:
   - `<!-- autocode:epic=<id> -->` -> the epic issue (also the single unit in a flat design).
   - `<!-- autocode:unit=<id>/<slug> -->` -> that unit's sub-issue.
   Record each unit's `{slug, key, status}`.
4. Compute the ready set:
   - Flat design: the one issue is the unit; ready iff its status is `todo`.
   - Multi-unit: a unit is ready iff its status is `todo` and every slug in its `depends-on` (from the unit file frontmatter) maps to a unit whose status is `done`. Units already `in-progress`/`in-review`/`done` are excluded.
   - If the ready set is empty, report why (all done, or all remaining are blocked on unfinished deps) and stop.
5. Select the unit. With `--unit <slug>`, pick that unit directly and error if it is not in the ready set. Otherwise present the ready units via `AskUserQuestion` (slug + one-line deliverable) and let the user pick one; under `--auto` with no `--unit`, skip the prompt and pick the sole ready unit, erroring if the ready set is empty or has more than one. Its sub-issue `key` is the ticket for the rest of the flow.
6. Ensure a worktree per `@~/.autocode/autocode/_config/guides/worktree.md` (based on the default branch, where deps are already merged). Inside it, delegate to `git-create-branch <key>` for the feature branch.
7. Transition state:
   - `provider/run.sh issue-tracker issue-transition <key> in-progress`.
   - Multi-unit: if the epic issue status is still `todo`, `provider/run.sh issue-tracker issue-transition <epic-key> in-progress`.
8. Seed the per-unit log. In the worktree, create `.autocode/design/<id>-<short>/progress/<slug>.md` with the header from the design-folder spec (slug, epic, branch, started date). Multi-unit only writes under the existing folder; flat uses slug `<short>`.
9. Seed the worktree state files (both gitignored; the Stop progress hook reads them):
   - `.autocode/.impl-context`: a JSON object with keys `design_id`, `shortname`, `slug`, `unit_key`, `epic_key` (empty string for flat), `progress_log` (absolute path to the per-unit log). The hook parses this with `jq`, so it must be valid JSON.
   - `.autocode/.progress-last-sha`: current `git rev-parse HEAD`.
10. Report: worktree path, branch, unit slug, sub-issue key, and next step (`/impl` to run the unit through to a PR, or `/impl-plan` then `/impl-execute` to drive it by hand). With `--auto`, emit these as a structured result block (worktree path, branch, slug, unit_key, epic_key, design_id) and omit the human next-step, so an orchestrator can thread the worktree path to later phases.

## Workflow (ticket / description mode)

1. Treat the arg as a ticket id (ticket mode) or `<type>: <description>` (description mode). No design epic, no unit selection, no progress log.
2. Ensure a worktree per `@~/.autocode/autocode/_config/guides/worktree.md` (based on the default branch); inside it, delegate to `git-create-branch`.
3. Report worktree path, branch, ticket id (if any), and next step.

## Rules

- Worktree base is the repo's default branch. Units merge to the default branch directly; there is no epic integration branch. A unit's dependencies being `done` (closed) means their code is already on the default branch the worktree is based on.
- Never branch from a dirty working tree on the default branch.
- Delegate branch creation to `git-create-branch`; never duplicate that logic.
- Pick exactly one ready unit per invocation. Re-run the skill to start another.
- The state files (`.autocode/.impl-context`, `.autocode/.progress-last-sha`) are gitignored. `/autocode-setup` and `/autocode-update` are the primary owners of `$repo_root/.autocode/.gitignore`; as a backstop (relocated config dir, or a repo set up before this was added), ensure it ignores them here (create if missing, append if absent).

$ARGUMENTS
