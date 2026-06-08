# Design PR body

Canonical recipe for the body of a design-doc PR. Imported by `design-plan-push`
(composes it at creation) and `pr-hygiene` (recomposes it on refresh) so the two
never diverge. A design PR's body is a rendered-doc link plus the repo PR
template filled from the design doc; it is never a code-diff summary.

## Detection

A PR is a design PR when its branch diff touches `.autocode/design/**` and no
source outside it: `git diff <base>...HEAD --name-only` is non-empty and every
path is under `.autocode/design/`. (The rendered-design link at the top of the
body, below, is a secondary marker.)

## Inputs

- `<folder>`: the design folder `.autocode/design/<id>-<shortname>/`. Callers
  that already resolved it pass it in. Otherwise discover it from the diff:
  `git diff <base>...HEAD --name-only | grep '^\.autocode/design/'`, then take
  the containing `<id>-<shortname>` directory (the one holding `DESIGN.md`).
- `<base>`: resolved base branch. `<branch>`: current branch ref
  (`git rev-parse --abbrev-ref HEAD`).

## Recipe

Compose to a temp file: `body="$(mktemp -d -t autocode-design-pr)/body.md"`.

1. Rendered-design link(s) at the very top, before any template section, so the
   reviewer's first click opens the formatted doc instead of a diff. Derive the
   host base URL:
   ```
   base_url=$(git remote get-url origin | sed -E 's#(git@|https://)([^:/]+)[:/]#https://\2/#; s#\.git$##')
   ```
   Write a `Rendered design` label, then the link
   `$base_url/blob/<branch>/.autocode/design/<id>-<shortname>/DESIGN.md` (add one
   per `units/<slug>.md` when multi-unit). The branch ref keeps links current as
   commits land during review; after merge the branch is gone, but fan-out writes
   the permanent link to `DESIGN.md` at the merge commit. (GitHub URL shape; the
   only supported host.)
2. Below the link, fill the repo PR template (`@.github/PULL_REQUEST_TEMPLATE.md`;
   the `pr-template` convention is the pointer). Strip its HTML comments. Fill
   sections from the design doc, not from a code diff:
   - `## Overview`: the `DESIGN.md` `## Summary`.
   - `## Problem Statement`: the design's motivation (from `## Summary` /
     `## Background`); keep under four bullets.
   - `## Architecture`: the `DESIGN.md` architecture diagram if it has one (the
     rendered-doc link already covers the full doc).
   - `## Checklist`: copy items verbatim; check
     `Documentation added or modified appropriately` (the design doc is the doc),
     leave the issue-mention item unchecked (no issue exists pre-fan-out), and
     mark the test-case item n/a (the PR is text).
3. Never hand-write an issue reference (`Closes`, `Refs`). Pre-fan-out there is
   no issue; post-merge fan-out owns linking.
