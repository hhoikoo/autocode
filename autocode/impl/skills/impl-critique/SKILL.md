# Impl critique

Critique the current implementation diff with a fan-out of parallel reviewers, verify findings adversarially, then present ranked results. Report only; applies nothing. Run before `/impl-push`.

Orchestrator-subagent shape: the main session assembles context and decides; `code-reviewer` subagents (one per dimension, plus refutation verifiers) do the reading and judging in parallel.

## Args

All optional:
- `--dims <list>`: comma-separated dimensions to run. `correctness` is always included. Default set: `correctness,security,performance`. Known dimensions: `correctness`, `security`, `performance`, `observability`, `standards`.
- `--base <ref>`: base to diff against. Default: the repo's default branch (the same base `impl-start` worktrees from).

## Scope

Review the local working tree plus the branch's committed work versus base:
- Committed: `git diff <base>...HEAD`.
- Uncommitted: `git diff HEAD` plus untracked files (`git status --porcelain`).

`<base>` defaults to the repo default branch; resolve it once and reuse. If `HEAD` already equals base (nothing committed) and the working tree is clean, stop with "no changes to critique".

## Workflow

1. Resolve `<base>` and build the diff (committed + uncommitted + untracked). If empty, stop.
2. Assemble shared review context once: the diff, the changed file list, and the repo conventions that bound a review (`CLAUDE.md` and `.claude/rules/` globs that match changed paths). Pass this verbatim to every reviewer so they judge against this repo, not generic taste.
3. Pick dimensions and scale to diff size. Tiny diff (under ~50 changed lines): `correctness` only, one reviewer. Otherwise the resolved `--dims` set. Skip anything CI already enforces (lint, format, type errors); name what you skipped.
4. Fan out reviewers in parallel: one `code-reviewer` (review task) per dimension, in a single message with multiple `Task` calls. The `security` reviewer gets the diff with commit messages and any PR/branch description stripped (framing bias suppresses detection). Each returns findings as `{file:line, dimension, severity, claim, evidence}` where `severity` is `Important` | `Nit` | `Pre-existing` and `evidence` is a one-line "how I verified against actual behavior".
5. Filter and dedup in the main session:
   - Drop any finding lacking a concrete `file:line` or a verification rationale.
   - Dedup by `file:line` + claim; when reviewers overlap, keep the most specific.
6. Adversarially verify each surviving `Important` finding. Fan out 3 `code-reviewer` (refute task) verifiers per finding in parallel, each prompted to refute and to default to invalid when uncertain. Minority-veto: a single credible `invalid` kills the finding. Do not verify `Nit` or `Pre-existing` (cheap; just cap).
7. Rank and present (see Output). No edits, no PR comments.

## Output

In-session report, ranked:
- `Important` (survived verification): each as `file:line` then the claim, one line.
- `Nit`: capped at 5; if more, append `(+N more nits)`.
- `Pre-existing`: collapsed to a count, expandable on request.
Footer: dimensions run, what was skipped (CI-enforced, diff-size scaling), and next step (`/impl-push`, or fix and re-run).

## Rules

- Report only. Never edit the working tree, never post comments. Acting on findings is the user's call.
- Every surfaced finding carries a `file:line` and a verification rationale. No-evidence findings are dropped, not demoted.
- Decisions (dimension choice, dedup, veto) stay in the main session; reviewers and verifiers are stateless and parallel-safe (read-only, no shared writes).
- Multi-agent review costs 3-10x a single pass. Scale reviewer count to diff size; do not fan out the full set on a trivial change.
- Delegate the reading and judging to `code-reviewer`; the skill orchestrates, it does not review inline.

$ARGUMENTS
