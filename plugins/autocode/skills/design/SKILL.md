---
name: design
description: "Stateless re-entrant /design orchestrator: reconstructs the design-lifecycle stage each turn from disk, the tracker, and the open design PR; dispatches one heavy phase off-context (plan/critique/push/iterate/fanout) as a background Workflow; gates the merge to the user; and hands off to the impl orchestrator. Every phase skill stays individually invocable."
---

Read through @~/.autocode/autocode/design/skills/design/SKILL.md and execute actions according to the instructions in the file. `$ARGUMENTS` is forwarded.
