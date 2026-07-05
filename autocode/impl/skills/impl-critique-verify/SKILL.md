# Impl critique verify

Scoped verification that the decided findings applied this fix round are resolved and that the fix commits introduced no new regressions. Read-only.

## Input

Always supplied by the caller:
- The decided findings applied this round, each with `file:line`, `severity`, `claim`, `fix`.
- The base ref.

The skill computes the fix-commit diff itself; the caller does not supply it.

## Workflow

1. Compute the fix-commit diff against the base ref (`git diff <base>...HEAD`, `git diff HEAD`, untracked via `git status --porcelain`).
2. For each supplied finding, confirm it is resolved in the current working tree at its `file:line`. Still open -> actionable.
3. Diff-scan the fix commits for NEW regressions outside the supplied set. A regression -> actionable.

## Output

A `DECIDE_SCHEMA`-compatible object, no preamble:

```
- file:line | <severity> | <claim> | <minimal fix>
```

Then a one-line tally: `kept N (important M, nit K), dropped D`.

`severity` MUST be exactly `Important` or `Nit`. `fix` MUST be populated for every `Important` survivor (it feeds `impl-execute --fix`). `dropped` is the count of supplied findings confirmed resolved. `tally` is the one-line summary above.

Low confidence: decline. Emit no structured object at all, so the workflow falls back to the full `reviewCycle`.

## Rules

- Read-only: never edit, write, or run mutating commands.
- Every supplied finding is accounted for: resolved -> counted in `dropped`; still-open -> `actionable`.
- Regressions found outside the supplied set are added to `actionable` too.
- Decline (no structured object) rather than guess on low confidence.

$ARGUMENTS
