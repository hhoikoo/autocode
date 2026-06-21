---
depends-on: [channel-core]
type: task
---

# Presence skills register, deregister, and list agents

## Summary

Three user-facing skills that manage an agent's presence in the file channel built by channel-core. `a2a-register` writes or refreshes this session's inbox card, `a2a-deregister` removes it on exit, and `a2a-agents` lists live agents on the repo. All three source the channel-core lib under `autocode/comms/lib/` for every file mutation, dir resolution, frontmatter write, and dead-agent reaping; none reimplements that logic. Identity binds to the tmux pane: each skill resolves "which agent am I" from `$TMUX_PANE` and no-ops with a one-line message when run outside tmux. Each skill ships as a body-only real file plus a thin shim, following the repo's shim+source layout.

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

1. Source the channel-core lib (`autocode/comms/lib/`); call its self-resolution and dir-resolution helpers. Do not duplicate their logic.
2. If `$TMUX_PANE` is unset, no-op with a clear one-line message ("not in tmux; agent presence skipped") and stop.
3. Resolve own tmux coordinates from `$TMUX_PANE`:
   - coords: `tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index}'`
   - pane id: `$TMUX_PANE` (the stable identity handle).
4. Resolve the main-worktree messages dir via the lib (git-common-dir based).
5. Take the agent name and task from `$ARGUMENTS`. Default the name from the session/window (e.g. `<session_name>-<window_index>`) when not supplied. Description defaults from the task or a short label.
6. Write/refresh the inbox `<name>.md` frontmatter via the lib (lock + tmp-then-rename). Fields written are owned by channel-core; see `autocode/comms/CLAUDE.md` for the authoritative card schema (name, description, tmux, pane, repo, task; `skills`/`state` omitted in v1). Re-registering the same pane updates the existing card in place rather than duplicating it (match on `pane:` == `$TMUX_PANE`).

### a2a-deregister

Best-effort removal of this session's presence on exit.

1. Source the lib; resolve self via `$TMUX_PANE`. No-op (silent-ish, one line) when unset.
2. Resolve the messages dir via the lib.
3. Find this session's inbox by matching `pane:` == `$TMUX_PANE`. Remove `<name>.md` plus its sidecars `.<name>.cursor`, `.<name>.lock/`, and `.<name>.rewake.pid` (kill a recorded poller PID first if present).
4. Best-effort throughout: a missing inbox or sidecar is not an error.

### a2a-agents

List live agents registered on the repo.

1. Source the lib; resolve the messages dir.
2. Call the lib `list-live-agents` reaper, which checks each inbox `pane:` against live `tmux list-panes -a` and prunes dead entries on access.
3. Print one row per live agent: name, task, state, and tmux coords. Mark self (matching `$TMUX_PANE`) when applicable.

### Shim shape

Each shim mirrors `plugins/autocode/skills/git-commit/SKILL.md`: frontmatter with `name` and `description`, body a single line `Read through @~/.autocode/autocode/comms/skills/<name>/SKILL.md and execute actions according to the instructions in the file.`, forwarding `$ARGUMENTS` where the skill takes args (register only).

## Testing

One runnable bash self-check (assert-based, no framework):

`autocode/comms/skills/a2a-register/test/smoke.sh`

It stubs `$TMUX_PANE` and points the lib at a temp messages dir, runs the register path, and asserts `<name>.md` is created with the expected card frontmatter (name, pane, tmux, repo, task). It then runs the a2a-agents list path and asserts the registered agent appears with its task and state. tmux-dependent send paths are out of scope here; the check validates the file-side mutations only.
