---
name: impl
description: "Orchestrate a fanned-out design epic end to end: stateless and re-entrant, it reconstructs unit state from the tracker each turn, launches a capped wave of per-unit background workflows, refills as they finish, cascades into newly-unblocked units on merge, prunes merged worktrees, and archives when every unit is done. Bare-ticket invocations keep the single-unit launch. Per-phase skills stay individually invocable."
---

Read through @~/.autocode/autocode/impl/skills/impl/SKILL.md and execute actions according to the instructions in the file. `$ARGUMENTS` is forwarded.
