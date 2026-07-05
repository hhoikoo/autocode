---
depends-on: [per-module-gapcheck, impl-recap-surface]
type: task
---

# Wire the Recap phase, convergence gate, and hygiene gate into the impl workflow

## Summary

Insert a `Recap` phase into `impl-workflow.mjs` between the fix loop and Push so a sonnet agent runs the new `impl-recap` skill on a clean tree and SHA-pins shipped-source blob URLs at the current HEAD, add `RECAP.md` to `impl-push`'s staged set so the recap lands in the unit PR, wire the post-Push convergence-gate action that draft-PRs and labels an unconverged unit, and gate the Hygiene phase on a path classification of the pushed changed files so `pr-hygiene` only runs when a doc/README/public-API file actually changed (folds D5). This is the tail edit of the impl-workflow.mjs serialization chain; it consumes `pr-draft.sh` and the `needsHuman` convergence flag from `scoped-verify-gate` and the `impl-recap` skill from `impl-recap-surface`.

## Implementation

Chain-tail edit to the impl-workflow runtime plus one `impl-push` staging change. No new files; all new artifacts (the `impl-recap` skill, `pr-draft.sh`, the `needsHuman` computation) are provided by the two upstream units.

### Files to modify

- `autocode/impl/skills/impl/scripts/impl-workflow.mjs` (chain tail: last editor of this file).
- `autocode/impl/skills/impl-push/SKILL.md` (stage `RECAP.md`).

### Recap phase

Insert `phase('Recap')` and its agent call in the gap between the fix-loop close (`impl-workflow.mjs:348`) and `phase('Push')` (`:350`). The agent runs sonnet, following the `impl-recap` skill via the existing `skill('impl-recap')` helper (`:39`), which `impl-recap-surface` creates under `autocode/impl/skills/impl-recap/`. Add a matching `meta.phases` entry `{ title: 'Recap', ..., model: 'sonnet' }` between the `Fix` (`:17`) and `Push` (`:18`) entries.

The wiring stays thin: the Recap agent reads `design_id`/`shortname`/`slug` from `.autocode/.impl-context` (per `impl-start/SKILL.md:37`) and the skill owns capturing `sha=$(git rev-parse HEAD)`, deriving the blob base URL from `git remote get-url origin`, SHA-pinning shipped-source blob URLs at that sha, and writing `RECAP.md` under `.autocode/design/<design_id>-<shortname>/recap/<slug>/`. Correctness precondition the placement guarantees: by `:348` every Execute/GapFix/Fix pass has committed (`impl-execute` commits each pass), so the tree is clean and HEAD is the last code commit; `RECAP.md` references only already-committed paths (it cannot pin itself or `PROGRESS.md`, which are finalized in the Push commit). Recap runs before Push and Push is plain non-force (`impl-push/SKILL.md:30`), so the pinned commit stays an ancestor of the pushed tip.

### Stage RECAP.md in the unit PR

Edit `impl-push/SKILL.md:20` (step 4) so the `git-commit` delegation stages `RECAP.md` alongside the code, `PROGRESS.md`, and `progress/<slug>.md` it already stages. This lands the recap on the unit branch and, on merge, in the design folder.

### Post-Push convergence-gate action

After the Push agent returns (`push.pr_url`, `:351-355`), add a conditional action: when `needsHuman` (the flag `scoped-verify-gate` computes from `remaining_important > 0 || remaining_gaps > 0`), call `provider/git-remote/github/pr-draft.sh` (created by `scoped-verify-gate`, wrapping `gh pr ready <n> --undo`) to convert the just-opened PR to draft, then apply the `needs-human` label idempotently (`gh label create needs-human --force` then `--add-label`, the repo's inline-create pattern per `issue-transition.sh:56`) plus a marking comment. The unit stays `in-review` (the PR exists); it never becomes `needs-recovery`, so the worktree is not deleted (`impl/SKILL.md:42`). When `needsHuman` is false the action is skipped and the PR stays ready.

### Hygiene gate (folds D5)

Wrap the currently-unconditional Hygiene phase (`impl-workflow.mjs:357-362`) in a conditional. Add a path predicate over `push.hygiene_files` (untyped `string[]` in `PUSH_SCHEMA:132-135`) that returns true when any changed path is documentation or a public-API surface (`.md`, `README*`, `CLAUDE.md`, and skill/agent/provider-contract definition files). Run `pr-hygiene` only when the predicate matches; otherwise skip the phase. `pr-hygiene`'s job is doc/PR-description currency, so a diff that touches no doc or interface file has nothing for it to do. No classifier exists today; this unit adds the predicate as a named boolean (per `.claude/rules/code-conventions.md`, extract complex conditions).

### Tail pipeline after this unit

```
  ... Fix loop close (:348)
        |
   phase('Recap')  sonnet impl-recap -> RECAP.md, SHA-pinned blobs at HEAD (clean tree)
        |
   phase('Push')   impl-push commits rollup incl. RECAP.md, opens PR (non-force)
        |
   if needsHuman -> pr-draft.sh (draft) + needs-human label/comment ; unit stays in-review
        |
   if hygieneRelevant(push.hygiene_files) -> phase('Hygiene') pr-hygiene ; else skip
```

### Tests that prove it

No unit-test harness for workflow scripts; verify by driving the flow (the `verify` skill). Run the impl workflow on a small unit and confirm: (a) `Recap` appears in the emitted phase list, positioned before `Push`; (b) `RECAP.md` is committed on the unit branch and renders in the file view with blob URLs pinned at the recap-time HEAD; (c) a unit left unconverged (`needsHuman` true) yields a draft PR carrying the `needs-human` label and stays `in-review`; a converged unit yields a ready PR; (d) the Hygiene phase runs only when a doc/README/public-API file is in `push.hygiene_files` and is skipped otherwise.
