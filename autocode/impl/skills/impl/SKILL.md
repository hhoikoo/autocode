# Impl

Orchestrate one design unit end to end: set up the worktree, then run plan -> execute -> review -> fix -> push -> hygiene as a background workflow, keeping the heavy work out of this session. Thin launcher: the phase logic lives in the delegated skills and the workflow script, not here.

The workflow runs each phase as its own agent with a per-phase model (opus for reasoning and review, sonnet for mechanical work) and does the fan-out the per-phase skills cannot (subagents cannot spawn subagents). Design-folder layout, `.impl-context` keys, and the unit DAG: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- A unit selector forwarded to `impl-start`: `--from-design <id|shortname>`, a `<ticket-id>`, or `<type>: <description>`. Optional when the current directory is already a set-up unit worktree.
- `--dims <list>`: review dimensions, forwarded to the review phase.

## Workflow

1. Set up the unit. If the current directory is already an autocode worktree on a feature branch with `.autocode/.impl-context`, reuse it. Otherwise delegate to `impl-start` (interactive: it presents the ready units and creates the worktree + branch + context). This is the only interactive step; capture the worktree path, `slug`, `unit_key`, and `design_id` from its report.

2. Resolve the workflow inputs:
   - `homeDir`: `echo "$HOME"`.
   - `base`: the repo's default branch (`git symbolic-ref --short refs/remotes/origin/HEAD` with the `origin/` prefix stripped; fall back to the local default branch).
   - `worktree`, `slug`, `unit_key`, `design_id` from step 1; `dims` from `--dims` when given.

3. Launch the workflow. Call the Workflow tool with:
   - `scriptPath`: `<homeDir>/.autocode/autocode/impl/skills/impl/scripts/impl-workflow.mjs` (resolve `<homeDir>` from step 2).
   - `args`: `{ homeDir, worktree, slug, unit_key, design_id, base, dims }`.
   The script runs every phase in the background with per-phase models. This session does not run the implementation, review, or PR work; it waits for the workflow to finish.

4. Report the workflow's final result: PR URL, branch, number of fix rounds, any remaining `Important` findings, and the review tally. Next step: `/pr-review` when reviews land.

## Rules

- Thin launcher. Do not implement, review, or open PRs inline; the workflow's agents run the delegated skills (`impl-plan`, `impl-execute`, the `impl-critique-*` skills, `impl-push`).
- Unit selection and worktree setup are `impl-start`'s job and run interactively in this session. Everything after is the workflow's job: background, model-pinned, out of this context.
- One unit per invocation. Re-run to start the next ready unit.

$ARGUMENTS
