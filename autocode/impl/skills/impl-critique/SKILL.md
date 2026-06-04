# Impl critique

Critique the current implementation diff: fan out per-dimension reviewers, run a challenge pass against their findings, then a decide pass that rules which survive, and present the ranked result. Report only; applies nothing. Run before `/impl-push`.

Composer of three leaf skills (`impl-critique-review`, `impl-critique-challenge`, `impl-critique-decide`), each executed by a read-only `code-reviewer` subagent. The same three skills back the `impl` orchestrator's review phase; this skill is their standalone, report-only front end. The main session assembles context and decides; the subagents read and judge in parallel.

## Args

All optional:
- `--dims <list>`: comma-separated dimensions to run. `correctness` is always included. Default set: `correctness,security,performance`. Known: `correctness`, `security`, `performance`, `observability`, `standards`.
- `--base <ref>`: base to diff against. Default: the repo's default branch (the same base `impl-start` worktrees from).

## Scope

Review the local working tree plus the branch's committed work versus base:
- Committed: `git diff <base>...HEAD`.
- Uncommitted: `git diff HEAD` plus untracked files (`git status --porcelain`).

Resolve `<base>` once and reuse. If `HEAD` already equals base and the working tree is clean, stop with "no changes to critique".

## Workflow

1. Resolve `<base>` and build the diff (committed + uncommitted + untracked). If empty, stop.
2. Assemble shared review context once: the diff, the changed file list, and the repo conventions that bound a review (`CLAUDE.md` and `.claude/rules/` globs matching changed paths). Pass this verbatim to every subagent so they judge against this repo, not generic taste.
3. Pick dimensions and scale to diff size. Tiny diff (under ~50 changed lines): `correctness` only, one reviewer. Otherwise the resolved `--dims` set. Skip anything CI already enforces (lint, format, types); name what you skipped.
4. Review (fan-out). Dispatch one `code-reviewer` subagent per dimension in a single message with multiple `Task` calls, each told to follow `impl-critique-review` for that dimension with the shared context. The `security` reviewer gets the diff with commit messages and any PR/branch description stripped (framing bias suppresses detection). Collect the findings, assign each a stable `id`, drop any lacking a concrete `file:line` or how-verified rationale, and dedup by `file:line` + claim (keep the most specific).
5. Challenge. Dispatch one `code-reviewer` subagent following `impl-critique-challenge` with the diff and the deduped findings (with their ids). Collect the per-id verdicts (`refuted|weakened|unrefuted` + reason).
6. Decide. Dispatch one `code-reviewer` subagent following `impl-critique-decide` with the findings and their challenges. Collect the final ranked actionable list and the tally.
7. Present (see Output). No edits, no PR comments.

## Output

In-session report built from the decide output, ranked:
- `Important` survivors: each as `file:line` then the claim and the minimal fix, one line.
- `Nit`: capped at 5; if more, append `(+N more nits)`.
- Dropped: collapsed to a count, expandable on request.
Footer: dimensions run, what was skipped (CI-enforced, diff-size scaling), and next step (`/impl-push`, or `/impl-execute --fix` then re-run).

## Rules

- Report only. Never edit the working tree, never post comments. Acting on findings is the user's call.
- Decisions about dimension choice, dedup, and finding ids stay in the main session; the leaf skills are stateless and parallel-safe (read-only, no shared writes).
- Delegate the reading and judging to `code-reviewer` subagents running the leaf skills; the skill orchestrates, it does not review inline.
- Scale reviewer count to diff size; multi-agent review costs 3-10x a single pass. Do not fan out the full set on a trivial change.

$ARGUMENTS
