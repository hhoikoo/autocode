# guides/

Fixed, cross-cutting procedural specs that skills `@`-import (like `design-folder.md` does from `design/`). Plugin-internal: unlike `conventions/`, nothing here is scaffolded into target repos, and unlike `output-styles/`, nothing is symlinked into the plugin tree. A guide is a single source of truth for a procedure shared by skills across feature-sets.

- `worktree.md`: how skills enter and tear down a git worktree to isolate repo changes. Imported by the design, impl, and git skills that mutate the repo.
- `svg-diagram.md`: a copy-and-edit SVG diagram template plus a `python3`/Node well-formedness check. Imported by design and impl skills that author a diagram where SVG reads better than ASCII.
