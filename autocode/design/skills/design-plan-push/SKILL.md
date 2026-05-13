# Design plan push

Open a PR for a written design doc.

## Args

`<ticket-num>` or `<feature-shortname>` (same discovery as `design-plan-critique`).

`--temp` plans are refused. The user must promote the temp plan to a tracked `.autocode/design/` directory first.

## Discovery

- If arg looks like a path: refuse (temp plans not supported here).
- Else glob `.autocode/design/<ticket-num>-*` or `*-<shortname>`.
- On no match, ask the user via `AskUserQuestion`.

## Workflow

1. Locate `.autocode/design/<ticket-num>-<shortname>/DESIGN.md`. Stop on no match.
2. Verify a worktree + feature branch exist for this ticket:
   - Check `git rev-parse --abbrev-ref HEAD` and confirm the branch encodes this ticket.
   - If not, delegate to `impl-start <ticket-num>` and continue inside the new worktree.
3. Stage the design directory: `git add .autocode/design/<ticket-num>-<shortname>/`.
4. Delegate to `git-commit` (forwards a context note describing the design proposal).
5. Delegate to `pr-create --lightweight`. The lightweight flag:
   - Skips PR-template sectioning.
   - Body becomes the plan's executive summary verbatim plus a bullet list of the plan's section headings.
   - Skips background `pr-hygiene` dispatch (the PR is text, not code, so hygiene assessments don't apply).
6. Report PR URL. Suggest `/design-plan-iterate` once reviews land.

## Rules

- Refuse `--temp` plans. Tell the user to promote to a tracked path first.
- Delegate aggressively. Do not inline commit logic, do not inline PR-body generation.
- The PR is text-only; never run a verify step.

$ARGUMENTS
