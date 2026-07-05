---
depends-on: [channel-core]
type: task
---

# Presence skills register, deregister, and list agents

## Summary

Three user-facing skills that manage an agent's presence in the file channel built by channel-core. `a2a-register` writes or refreshes this session's agent card, `a2a-deregister` removes its agent dir on exit, and `a2a-agents` lists live agents on the repo. All three are thin wrappers over the channel-core CLI: each skill step runs `bash ~/.autocode/autocode/comms/lib/channel.sh <subcommand> ...` (one subcommand per Bash call; shell state does not persist between skill steps, so nothing is sourced). Identity binds to the tmux pane: each skill resolves "which agent am I" from `$TMUX_PANE` and no-ops with a one-line message when run outside tmux. Receiving is opt-in (DESIGN.md decision 9): a session gets messages only after registering (or being spawned); the outbound skills auto-register via the same `register` subcommand. Each skill ships as a body-only real file plus a thin shim, following the repo's shim+source layout.

## Implementation

Six files, three skill pairs. Real files are body-only (no frontmatter). Each shim carries only `name`+`description` frontmatter and a single `@~/.autocode/...` read line.

Real skills:

- `autocode/comms/skills/a2a-register/SKILL.md`
- `autocode/comms/skills/a2a-deregister/SKILL.md`
- `autocode/comms/skills/a2a-agents/SKILL.md`

Shims:

- `plugins/autocode/skills/a2a-register/SKILL.md`
- `plugins/autocode/skills/a2a-deregister/SKILL.md`
- `plugins/autocode/skills/a2a-agents/SKILL.md`

Skill names are globally unique (`a2a-` prefix; not used by any existing feature-set).

### a2a-register

Register or refresh THIS session as a named agent.

1. If `$TMUX_PANE` is unset, no-op with a clear one-line message ("not in tmux; agent presence skipped") and stop.
2. Take the agent name and task from `$ARGUMENTS`; run `bash ~/.autocode/autocode/comms/lib/channel.sh register [name] [task]`. The subcommand owns everything: messages-dir resolution, the default name (`<session_name>-<window_index>`; channel-core owns the scheme), the card schema (name, description, pane, server, task; see `autocode/comms/CLAUDE.md`), the tmp+mv card write, `new/`/`cur/` creation, and refresh-in-place when this pane is already registered. The skill supplies args and reports the result; it duplicates no logic.

### a2a-deregister

Best-effort removal of this session's presence on exit.

1. Same not-in-tmux guard.
2. Run `bash ~/.autocode/autocode/comms/lib/channel.sh deregister`. The subcommand finds this pane's agent dir, kills a recorded `rewake.pid` poller if present, and removes the dir. Best-effort throughout: a missing dir or sidecar is not an error. (The `SessionEnd` cleanup hook in delivery-hooks does the same automatically; this skill is the manual path.)

### a2a-agents

List live agents registered on the repo.

1. Run `bash ~/.autocode/autocode/comms/lib/channel.sh agents`. The subcommand reaps dead agents (pane AND server-pid liveness) and prints the live set.
2. Present one row per live agent: name, task, and display coordinates derived at read time (`tmux display-message -p -t "$pane"`; coords are never stored, DESIGN.md File format). Mark self (matching `$TMUX_PANE`) when applicable.

### Shim shape

Each shim mirrors `plugins/autocode/skills/git-commit/SKILL.md`: frontmatter with `name` and `description`, body a single line `Read through @~/.autocode/autocode/comms/skills/<name>/SKILL.md and execute actions according to the instructions in the file.`, forwarding `$ARGUMENTS` where the skill takes args (register only).

## Testing

One runnable bash self-check (assert-based, no framework):

`autocode/comms/skills/a2a-register/test/smoke.sh`

It stubs `$TMUX_PANE` and the tmux lookups, points the lib at a temp messages dir, runs the `register` subcommand, and asserts `<name>/card.md` is created with the expected card frontmatter (name, pane, server, task) and that `new/` and `cur/` exist. It then runs the `agents` subcommand and asserts the registered agent appears with its task. tmux-dependent paths are out of scope here; the check validates the file-side mutations only.
