---
depends-on: [svg-diagram-guide]
type: story
---

# Impl recap surface and canonical unit-PR body

## Summary

Make a shipped unit self-documenting. Add the `impl-recap` skill (sonnet), which builds a per-unit `recap/<slug>/RECAP.md` mechanically from the branch diff and the now-populated `progress/<slug>.md`: a headline, a narrative, data/contract deltas, a file tree, 3-8 SHA-pinned key-change excerpts with `svg-diagram-guide` infra SVGs, and the leftover `remaining_important` / `remaining_gaps`. Add `autocode/impl/impl-pr-body.md`, the canonical recipe for a unit code PR's body (sibling of `design-pr-body.md`), `@`-imported by `pr-create` (composer) and `pr-hygiene` (recomposer) so the two never diverge. Add the impl-PR detection and recompose branch to `pr-hygiene`, mirroring its existing design-PR branch. Extend the `design-folder.md` layout with the living `recap/<slug>/` folder. This unit creates all new files off the `impl-workflow.mjs` chain; the sibling `recap-phase-wiring` unit inserts the Recap phase that invokes `impl-recap`.

## Implementation

Deliverable: the recap artifact, its skill, the canonical unit-PR-body recipe, its two `@`-import call sites, and the `design-folder.md` layout extension. No edit to `impl-workflow.mjs` (that is `recap-phase-wiring`).

### Files to create

- `autocode/impl/skills/impl-recap/SKILL.md` (body-only, no frontmatter; `check-plugin-shape.sh` rejects a leading `---`, per prompt-engineering.md). Follows the leaf-skill body shape of `impl-gapcheck/SKILL.md:1-35`.
- `plugins/autocode/skills/impl-recap/SKILL.md` (flat shim: frontmatter with `name: impl-recap`, a `description` carrying a "Use when..." trigger, `model: sonnet`, plus the one-line `@~/.autocode/autocode/impl/skills/impl-recap/SKILL.md` read body). Mirrors `plugins/autocode/skills/impl-gapcheck/SKILL.md:1-7`. `impl-recap` is globally unique across feature-sets (DESIGN.md:58).
- `autocode/impl/impl-pr-body.md` (body-only, no frontmatter; sibling of `autocode/design/design-pr-body.md:1-29`). Canonical recipe for a unit code PR body.

### Files to modify

- `autocode/pr/skills/pr-create/SKILL.md`: at step 4 body generation (`:24-35`) add a unit-PR branch: when the detection rule in `@~/.autocode/autocode/impl/impl-pr-body.md` matches, compose the body per that recipe instead of the generic template fill. Symmetric to how `design-plan-push/SKILL.md:26` composes `design-pr-body.md`. `pr-create` (not `impl-push`) owns composition because `impl-push:29` bars inlining PR-body generation and delegates to `pr-create` at `impl-push:21` step 5.
- `autocode/pr/agents/pr-hygiene.md`: add an impl-PR branch parallel to the design-PR branch at `:28-31`, placed before the generic step-6 draft (`:42-48`). When the diff matches the unit-PR marker, recompose the body via `@~/.autocode/autocode/impl/impl-pr-body.md` (self-discovering its inputs from the diff) and apply with `provider/run.sh git-remote pr-body-edit`, then stop, exactly as the design branch does. Keeps the recomposed body identical to what `pr-create` first wrote.
- `autocode/design/design-folder.md`:
  - Contents tree (`:37-43`): add `recap/<slug>/          # per-unit recap folder; living` after the `progress/<slug>.md` line (`:42`).
  - Living-set sentence (`:45`): extend so `recap/<slug>/` joins `PROGRESS.md` and `progress/*.md` as living (written during implementation).
  - Committed-count sentence (`:53`): `All four are committed` -> `All five are committed`.
  - Flat-design paragraph (`:49`): note `recap/<shortname>/` alongside `progress/<shortname>.md` as the flat design's per-unit artifacts.
  - New `## recap/<slug>/` section after the `## progress/<slug>.md` section (`:137-150`), mirroring its shape: owned solely by that unit's worktree; holds `RECAP.md` and its sibling SVG assets; written at the Recap phase; the canonical description of what `impl-recap` produces.
- `autocode/impl/CLAUDE.md`: add an `impl-pr-body.md` importer paragraph mirroring `design/CLAUDE.md:9` (recipe imported by `pr-create` at compose, `pr-hygiene` at recompose, both `@`-import so the body never diverges); add `impl-recap` to the per-phase skill list (`:15-18`).
- `autocode/impl/skills/impl-start/SKILL.md` (optional, low priority): at step 8 (`:35`), alongside seeding `progress/<slug>.md`, optionally create the `recap/<slug>/` directory. Not required: `impl-recap` creates the folder at recap time; seeding only pre-stages it.

### impl-recap skill contract

Input (from the Recap-phase caller in `recap-phase-wiring`): the design folder and `<slug>` (from `.autocode/.impl-context`), the base ref, the current HEAD sha, and the surviving `remaining_important` / `remaining_gaps` tallies. The skill computes its own diff with read-only git (as `impl-gapcheck/SKILL.md:7` does); the model authors only prose, everything else is mechanical from the diff.

`RECAP.md` sections:

```
Headline          one-line prose
Narrative         prose, drawn from progress/<slug>.md
Data / contract   mechanical: schema / API / CLI deltas from the diff
File tree         mechanical: name-status rendered as a tree
Key changes       3-8 SHA-pinned blob excerpts + infra SVGs (@svg-diagram-guide)
Remaining         surfaced remaining_important + remaining_gaps
```

SVG and blob handling (DESIGN.md decision 9, `:78`):

- A relative-path SVG under `recap/<slug>/` is the primary surface; it renders in the `RECAP.md` file view even on a private repo. Follow the template and the runtime validator (`python3` / Node tag-balance, never `xmllint`) from `@~/.autocode/autocode/_config/guides/svg-diagram.md` (created by the `svg-diagram-guide` dependency).
- SHA-pin every blob URL at the recap-time HEAD; branch-ref URLs die after merge or archive.
- Gate any PR-description raw-URL SVG embed on `gh repo view --json isPrivate` (camo cannot auth a private-repo raw URL); private -> blob-link only.
- The Recap phase runs before Push (`recap-phase-wiring`), so the pinned HEAD is an ancestor of the pushed tip. `RECAP.md` pins only already-shipped source blobs, never itself or `PROGRESS.md` (both finalized in the Push commit) (DESIGN.md `:104`).

Output: the `RECAP.md` path plus the PR-embed-safe flag and any pinned SVG asset paths, for the PR body to consume. The exact result schema is fixed by `recap-phase-wiring` (the workflow unit), not here, the same way `impl-gapcheck/SKILL.md:28` defers `GAPCHECK_SCHEMA` to the workflow.

### impl-pr-body.md recipe shape

Mirrors `design-pr-body.md:1-29` structure but for a unit code PR (research `impl-pr-body-recipe-mirror`, `unit-pr-body-composer`):

- Title + intent: canonical recipe for a unit code PR body; composed by `pr-create`, recomposed by `pr-hygiene`; both `@`-import so it never diverges. Unlike the design recipe, a unit body summarizes code and links its `RECAP.md`.
- `## Detection`: mirror the design-PR check (`pr-hygiene.md:28`). A unit PR is one whose branch diff contains a committed `recap/<slug>/RECAP.md` (the impl marker; committed in the Push commit, so it is in `git diff <base>...HEAD --name-only`) and at least one source path outside `.autocode/design/`. This distinguishes it from a design PR (design-folder-only) and a plain PR (no recap artifact). `.autocode/.impl-context` is gitignored (`design-folder.md:53`) so it cannot be the diff marker; a committed `progress/<slug>.md` is the fallback marker.
- `## Inputs`: self-discovered from the diff (design folder, `<slug>`, base, branch, RECAP.md path), so both call sites resolve them the same way, matching `design-pr-body.md:9-12`.
- `## Recipe`: link the rendered `RECAP.md` at the top (SHA-pinned, GitHub blob shape as `design-pr-body.md:18-22`), then fill the repo PR template (`@.github/PULL_REQUEST_TEMPLATE.md`) from the RECAP summary; embed the infra SVG only when the repo is public. Never hand-write an issue reference (`Closes` / `Refs`); the close line stays owned by `pr-create` step 6 / `pr-issue-link` (`pr-create/SKILL.md:31,58`).

### Tests that prove it

Workflow scripts have no unit harness; verify by driving the flow (DESIGN.md `:107-109`):

- Run `impl-recap` on a small landed unit; confirm `RECAP.md` renders in the file view with a working relative-path SVG and SHA-pinned excerpts, and that `remaining_important` / `remaining_gaps` surface.
- Open a unit PR through `impl-push` -> `pr-create`; confirm the body is the RECAP-linked recipe output, not the generic template fill, and carries no hand-written `Closes`.
- Run `pr-hygiene` on that PR; confirm the impl-PR branch fires (not the design branch, not the generic draft) and the recomposed body is byte-identical to what `pr-create` wrote.
- Confirm the private-repo path suppresses the PR-description SVG embed (blob-link only) while `RECAP.md` still renders.
- Validate the emitted SVG with `python3 -c 'import xml.dom.minidom'` (never `xmllint`), per `svg-diagram.md`.

### Boundary

```
  impl-workflow.mjs Recap phase   -> invokes impl-recap        [recap-phase-wiring, NOT this unit]
  impl-recap (this unit)          -> writes recap/<slug>/RECAP.md
  impl-push step 5 -> pr-create   -> composes body via impl-pr-body.md   [this unit adds the branch]
  pr-hygiene                      -> recomposes body via impl-pr-body.md [this unit adds the branch]
```

Chain: this unit edits `design-folder.md` after `svg-diagram-guide` (both touch it; A1 after A3 per DESIGN.md `:50-51,66`). No `impl-workflow.mjs` edit here, so it stays off that serialization chain.
