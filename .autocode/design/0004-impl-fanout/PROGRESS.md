# Progress: impl-fanout

## gapcheck-leaf-skill — 2026-06-09

Unit: #48
Adds the `impl-gapcheck` leaf skill and its plugin shim. The skill reads a design folder's unit files, checks each unit's implementation against the design spec, and surfaces gaps as a ranked finding list. It also registers itself in the `autocode/impl/CLAUDE.md` feature-set index.
## execute-no-commit-scope — 2026-06-09

Unit: #47

Added `--no-commit` flag to `impl-execute` and `--module <name>` flag for per-module fanout. The two flags are independent and compose with `--auto`. Under `--no-commit`, the `git-commit` delegation is suppressed entirely; all changes land in the working tree unstaged. Under `--module`, execution is scoped to the named group in the plan's `## Module partition` section (`foundation` resolves to `### Foundation`; any other name matches a `### Modules` entry). Both flags are described in the workflow steps and the rules section.
## plan-module-partition — 2026-06-09

Unit: #49
Added a `## Module partition` section to the `impl-plan` skill (`autocode/impl/skills/impl-plan/SKILL.md`). The section directs the planner to emit a foundation set plus file-disjoint module groups (or an explicit non-partitionable statement) as the final planning step, so the workflow's Partition agent can transcribe the split from the plan file without re-deriving it. 23 lines added, 2 changed.
