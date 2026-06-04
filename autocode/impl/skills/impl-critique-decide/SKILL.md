# Impl critique decide

Adjudicate review findings against their challenges and emit the final actionable list. The caller supplies the findings and the per-finding challenges; weigh each, rule keep-or-drop, and state the minimal fix for survivors. Decision only; read-only.

## Input

Always supplied by the caller:
- The findings, each with an `id`, `file:line`, `severity`, and `claim`.
- The challenges, each keyed by `id`: `refuted|weakened|unrefuted` plus a reason.

## Workflow

For each finding, weigh the claim against its challenge:
- `refuted` with a credible, code-grounded reason -> drop.
- `weakened` -> keep at the reduced severity (often demote `Important` -> `Nit`).
- `unrefuted` -> keep at the stated severity.

When the challenge to an `Important` finding is not credible, keep it: a missed real bug costs more than a kept nit. For each survivor, state the minimal fix that resolves it.

## Output

Ranked actionable list (`Important` first), no preamble:

```
- file:line | <severity> | <claim> | <minimal fix>
```

Then a one-line tally: `kept N (important M, nit K), dropped D`.

## Rules

- Read-only: decide, do not edit. The fix directive feeds `impl-execute --fix`.
- Default to keeping `unrefuted` and `Important` findings; drop only on a credible, code-grounded refutation.
- Every supplied finding is accounted for: kept (with a fix) or dropped (counted).
