# Impl recap

Build a per-unit `recap/<slug>/RECAP.md` from the branch diff and the now-populated `progress/<slug>.md`, so a shipped unit is self-documenting. Read-only on source: the only writes are `RECAP.md` and its sibling SVG assets under `recap/<slug>/`. Sonnet skill: the model authors only prose (Headline, Narrative); everything else is mechanical from the diff. Distinct from `impl-gapcheck` (checks spec coverage) and `impl-critique` (checks correctness/quality): recap summarizes what a shipped unit did.

## Input

Supplied by the Recap-phase caller (contract fixed by `recap-phase-wiring`, not here): the design folder and `<slug>` (from `.autocode/.impl-context`), the base ref, the current HEAD sha, and the surviving `remaining_important` / `remaining_gaps` tallies. Do not fish for these; take them as given.

Compute the diff yourself with read-only git, exactly as `impl-gapcheck/SKILL.md` does: `git diff <base>...HEAD`, `git diff HEAD`, `git status --porcelain`, and `git diff <base>...HEAD --name-status`.

## Workflow

Build `recap/<slug>/RECAP.md` with these sections, in order:

- `Headline`: one-line prose summary of what shipped. Model-authored.
- `Narrative`: prose drawn from `progress/<slug>.md`. Model-authored.
- `Data / contract`: mechanical. Schema / API / CLI deltas extracted from the diff (added/removed flags, signatures, data shapes). No prose invention beyond labeling.
- `File tree`: mechanical. `git diff <base>...HEAD --name-status` rendered as a tree.
- `Key changes`: 3-8 SHA-pinned blob excerpts plus infra SVG(s). See `## SVG and blob handling`.
- `Remaining`: surface the caller-supplied `remaining_important` + `remaining_gaps` tallies verbatim.

## SVG and blob handling

DESIGN.md decision 9: `recap/<slug>/RECAP.md`'s relative-path SVG is the primary surface; a PR-description SVG embed is secondary and gated.

- Author a relative-path SVG under `recap/<slug>/` embedded in `RECAP.md`; it renders in the file view even on a private repo. Copy the skeleton and issue the validation Bash call yourself, per `@~/.autocode/autocode/_config/guides/svg-diagram.md`. Validate with `python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' <path>` (Node tag-balance fallback), never `xmllint`.
- SHA-pin every blob URL at the recap-time HEAD sha the caller supplied; branch-ref URLs die after merge or archive.
- Gate any PR-description raw-URL SVG embed on `gh repo view --json isPrivate`; a private repo means blob-link only (camo cannot auth a private-repo raw URL). The relative-path SVG inside `RECAP.md` renders regardless.
- `RECAP.md` pins only already-shipped source blobs at the captured HEAD; never itself or `PROGRESS.md` (both finalized in the later Push commit). The Recap phase runs before Push, so the pinned HEAD is an ancestor of the pushed tip.

## Output

The `RECAP.md` path, the PR-embed-safe flag (public repo -> true), and any pinned SVG asset paths, for the PR body to consume. The exact result schema is fixed by the workflow unit (`recap-phase-wiring`), not here, the same way `impl-gapcheck/SKILL.md` defers `GAPCHECK_SCHEMA` to the workflow.

## Rules

- Read-only on source; writes confined to `recap/<slug>/`.
- Mechanical sections (`Data / contract`, `File tree`, `Key changes`, `Remaining`) stay mechanical: no invented data. Prose only in `Headline` and `Narrative`.
- Never `xmllint`.
- Never pin an uncommitted path in a blob URL.

leanness: model authors only Headline + Narrative; all structural content is mechanical from the diff. Upgrade path (richer analysis) only if recaps prove too thin.
