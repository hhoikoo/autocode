---
depends-on: [workflow-progress-logging]
type: task
---

# Add an SVG diagram guide and offer it in the Architecture spec

## Summary

Add `autocode/_config/guides/svg-diagram.md`, a fixed hand-authored SVG diagram template that skills `@`-import when a diagram reads better as SVG than as ASCII art, and point the `design-folder.md` Architecture bullet at it. The guide ships a copy-and-edit `<svg>` skeleton (one `<marker>` arrowhead, a small set of `<style>` classes, rounded-rect boxes with 2-4 word labels on manual grid coordinates) and a validation step the authoring model runs as a Bash call: parse with `python3` (`import xml.dom.minidom`) or a short Node tag-balance check, never `xmllint` (absent on a minimal Linux box, reintroducing the dependency the epic avoids). No renderer binary and no manifest edit: guides are plugin-internal `@`-imported specs, not scaffolded or symlinked. This unit edits `design-folder.md` and so is chained after `workflow-progress-logging` to keep the shared file's edits linear.

## Implementation

Deliverable: a new guide file plus a one-bullet edit that makes SVG a documented alternative to ASCII diagrams in a design doc's Architecture section.

Files to create:

- `autocode/_config/guides/svg-diagram.md` (body-only, no frontmatter). A fixed procedural spec following the `worktree.md` shape (`autocode/_config/guides/worktree.md:1-3`): a lead paragraph stating what the guide is and who `@`-imports it, then the template and the validation procedure. Contents the guide must specify:
  - A ready-to-edit `<svg>` skeleton with an explicit `viewBox`, exactly one reusable `<marker>` arrowhead in `<defs>`, a small set (~4) of named `<style>` classes (box fill/stroke, label text, edge line, edge arrow), rounded-rect (`<rect rx>`) boxes carrying 2-4 word labels, and connectors placed on manually-chosen grid coordinates. No auto-layout, no renderer binary.
  - A validation step, run by the authoring model as a Bash call: well-formedness via `python3 -c` using `xml.dom.minidom`, with a ~20-line Node tag-balance check as the fallback when `python3` is absent. The guide states explicitly that `xmllint` is never used (research finding `svg-validation-runtime`; rationale `DESIGN.md` "SVG guide" testing note).
  - A note that the guide is the sole locus of the SVG procedure; the skills that author SVG (`design-plan`, and later `impl-recap`) `@`-import it and issue the validation Bash call themselves rather than restating the steps.

Files to modify:

- `autocode/design/design-folder.md:61` (the Architecture bullet, currently `Include an ASCII diagram when components interact or data crosses a boundary; omit the diagram for a single-file change.`): extend it so the diagram may be ASCII or an SVG authored per `@~/.autocode/autocode/_config/guides/svg-diagram.md`, keeping the "when components interact / omit for single-file" trigger unchanged. This is the same shared file that `workflow-progress-logging` edits at `:146` (progress-entry format) and that `impl-recap-surface` later edits (recap section); the `depends-on` on `workflow-progress-logging` exists to serialize these edits, not for a logical dependency (`DESIGN.md` design-folder.md chain, research finding `design-folder-svg-line`).
- `autocode/_config/guides/CLAUDE.md`: add a one-line bullet for `svg-diagram.md` beside the existing `worktree.md` bullet, so the directory keeps documenting its own contents (`autocode/_config/guides/CLAUDE.md:5-6`).

Out of scope: the sibling ASCII-diagram prescriptions at `design-plan/SKILL.md:39` and `design-unit-author.md:28` are candidate wider edits but the plan scopes this unit to `design-folder.md:61` (research finding `design-folder-svg-line`). No plugin manifest, symlink, or scaffold change: per `autocode/_config/guides/CLAUDE.md:3` guides are neither scaffolded into target repos nor symlinked into the plugin tree, and are referenced only via the `@~/.autocode/autocode/_config/guides/svg-diagram.md` import path.

Reference wiring:

```
  skill (design-plan, impl-recap)
     |  @-import
     v
  autocode/_config/guides/svg-diagram.md   <-- new: template + python3/Node validation
     ^  points at
     |
  autocode/design/design-folder.md:61 (Architecture bullet: ASCII or SVG)
```

Tests that prove it: copy the guide's `<svg>` skeleton verbatim and confirm it validates through the guide's own procedure, `python3 -c 'import xml.dom.minidom; xml.dom.minidom.parse(path)'` (and the Node tag-balance fallback), with no invocation of `xmllint`; confirm `design-folder.md:61` now names the SVG option and the `@`-import path resolves to the new guide; confirm no manifest or symlink was touched.
