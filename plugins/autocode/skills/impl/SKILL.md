---
name: impl
description: Implement the unit of work set up by impl-start. Loads the authoritative design from disk, turns it into a concrete per-file task list (pausing for approval unless --auto), implements against scope, commits at checkpoints, and stops at ready-for-review for impl-critique. Runs between impl-start and impl-critique.
---

Read through @~/.autocode/autocode/impl/skills/impl/SKILL.md and execute actions according to the instructions in the file. `$ARGUMENTS` is forwarded.
