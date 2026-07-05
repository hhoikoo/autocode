# Impl PR body

Canonical recipe for the body of a unit code PR. Composed by `pr-create` at creation and recomposed by `pr-hygiene` on refresh; both `@`-import it so the body never diverges. Unlike `design-pr-body.md` (a rendered-doc link), a unit body summarizes the code change and links its `recap/<slug>/RECAP.md`.

## Detection

A unit PR is one whose branch diff contains a committed `recap/<slug>/RECAP.md` (the impl marker, committed in the Push commit, so present in `git diff <base>...HEAD --name-only`) AND at least one source path outside `.autocode/design/`. This distinguishes it from a design PR (design-folder-only, `design-pr-body.md` Detection) and a plain PR (no recap artifact). `.autocode/.impl-context` is gitignored (`design-folder.md` `## Contents`) so it cannot be the diff marker; when `recap/<slug>/RECAP.md` is not yet committed, a committed `progress/<slug>.md` is the fallback marker.

## Inputs

Self-discovered from the diff so both call sites resolve them identically (matching `design-pr-body.md` Inputs):

- `<folder>`: the design folder `.autocode/design/<id>-<shortname>/`. Discover from `git diff <base>...HEAD --name-only | grep '^\.autocode/design/'`, then take the containing `<id>-<shortname>` directory.
- `<slug>`: the unit slug, the `recap/<slug>/` (or `progress/<slug>.md`) path component under `<folder>`.
- `<base>`: resolved base branch. `<branch>`: current branch ref (`git rev-parse --abbrev-ref HEAD`).
- `<recap>`: `<folder>/recap/<slug>/RECAP.md`.

## Recipe

Compose to a temp file: `body="$(mktemp -d "${TMPDIR:-/tmp}/autocode-impl-pr.XXXXXX")/body.md"`.

1. At the very top, before any template section, a `Recap` label plus a SHA-pinned GitHub blob link to `<recap>`. Derive the host base URL the same way as `design-pr-body.md`:
   ```
   base_url=$(git remote get-url origin | sed -E 's#(git@|https://)([^:/]+)[:/]#https://\2/#; s#\.git$##')
   ```
   Write the link as `$base_url/blob/<sha>/<recap>`, pinned at the branch/HEAD sha (not the branch ref: a unit PR's tip keeps moving during review, and the blob link should track it, so re-pin at the current HEAD sha whenever this recipe recomposes).
2. Below the link, fill the repo PR template (`@.github/PULL_REQUEST_TEMPLATE.md`; the `pr-template` convention is the pointer) from the RECAP summary, not from a raw diff:
   - `## Overview`: the RECAP `Headline`.
   - `## Problem Statement`: the RECAP `Narrative`, kept under four bullets.
   - `## Architecture`: the RECAP `Data / contract` section, plus the infra SVG embed only when the repo is public (`gh repo view --json isPrivate` -> `false`; a private repo suppresses the raw-URL embed since camo cannot auth it, per DESIGN.md decision 9).
   - Strip HTML comments (template instructions, not content). Copy checklist items character-for-character; only flip `[ ]` to `[x]` when satisfied.
3. Never hand-write an issue reference (`Closes`, `Refs`). The close line stays owned by `pr-create` step 6 / `pr-issue-link`.
