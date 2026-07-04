# Impl audit

Whole-repo over-engineering audit. Scan the tree (not a diff) for what to delete, simplify, or replace with stdlib / native equivalents. Ranked report, biggest cut first. Report-only: lists findings, applies nothing. The repo-wide counterpart of `impl-critique`'s `leanness` dimension, which reviews a diff.

## Args

All optional:
- `<path>`: limit the scan to a subtree. Default: the repo root (`git rev-parse --show-toplevel`).
- Freeform note: extra focus (e.g. "the auth module"). Context, not a scope expander.

## Scope

Read the working tree. Hunt:
- Dependencies the stdlib or platform already ships.
- Single-implementation interfaces, factories with one product, wrappers that only delegate.
- Files exporting one thing, dead flags, config nobody sets.
- Hand-rolled stdlib, code that shrinks with no behavior change.

Bound findings to the repo's own standards: read `CLAUDE.md` and `.claude/rules/` so each is over-engineering by this repo's conventions, not generic taste.

## Tags

- `delete`: dead code, unused flexibility, speculative feature. Replacement: nothing.
- `stdlib`: hand-rolled thing the standard library ships. Name the function.
- `native`: dependency or code doing what the platform already does. Name the feature.
- `yagni`: abstraction with one implementation, config nobody sets, layer with one caller.
- `shrink`: same logic, fewer lines. Show the shorter form.

## Output

One line per finding, ranked biggest cut first:

`<tag>: <what to cut>. <replacement>. [path:line]`

End with `net: -<N> lines, -<M> deps possible.` Nothing to cut: `Lean already. Ship.`

## Rules

- Read-only. List findings, apply nothing. Acting on them is the user's call.
- Leanness only. Correctness bugs, security holes, and performance go to `impl-critique`, not here.
- Never flag the `Lazy is not careless` carve-outs (active style) or a single smoke test / assert-based self-check; those are the leanness minimum, not bloat.
- Every finding cites a concrete path; no citation, no finding.

$ARGUMENTS
