---
depends-on: [channel-core]
type: task
---

# Spawn skill launches a seeded agent in a tmux window

## Summary

One user-facing skill, `comms-spawn`, that delegates a side task to a fresh Claude session. It runs the handover skill inline to produce a self-contained takeover prompt (skills compose in-context, not as subprocesses: this session executes handover's steps and therefore has the written `handover.md` path in context), creates a tmux target (a new window by default or a detached session with `--session`), launches `claude` there, seeds it with a one-line read prompt pointing at the handover file, then registers the new agent via the channel-core `register` subcommand so it is immediately addressable. All tmux targeting uses the captured `%N` pane id (stable for the server's lifetime), never stored window coordinates. Every tmux call is guarded by `has-session`; outside tmux the skill refuses with a one-line message. The new session resolves its own identity from `$TMUX_PANE` via the channel-core SessionStart inject hook once it boots.

## Implementation

Two files, one skill pair. Real file is body-only (no frontmatter). The shim carries only `name`+`description` frontmatter and a single `@~/.autocode/...` read line. Skill name `comms-spawn` is globally unique (`comms-` prefix; not used by any existing feature-set).

Real skill:

- `autocode/comms/skills/comms-spawn/SKILL.md`

Shim:

- `plugins/autocode/skills/comms-spawn/SKILL.md`

### comms-spawn

Delegate a task to a new seeded Claude session in tmux. Workflow:

1. Parse `$ARGUMENTS`: a required task description, an optional `--session` flag (new detached session instead of a new window in the current session), and an optional target agent name. Default the name via the channel-core default scheme (`<session_name>-<window_index>` of the NEW window; channel-core owns the scheme, so a later manual `comms-register` in the spawned session computes the same default).
2. Guard: if `$TMUX_PANE` is unset (not inside tmux), report a one-line refusal and stop. Spawned agents bind identity to a tmux pane, so the spawner must itself run in tmux.
3. Resolve the main-worktree root and messages dir via `bash ~/.autocode/autocode/comms/lib/channel.sh resolve-dir` (one subcommand per Bash call; nothing sourced across steps).
4. Run the handover skill inline, forwarding the task description. Its steps execute in this session; after its final "print the path" step the `handover.md` path is in context. Do not reimplement handover, and do not model this as a subprocess with captured stdout (skills have no such mechanism).
5. Create the tmux target and capture the pane id in one step, setting the working dir with `-c` so the child `claude` boots in the right repo (default the main-worktree root; new windows otherwise inherit the spawner's cwd, which may be a linked worktree):
   - default (new window in current session): `tmux new-window -c <repo-root> -P -F '#{pane_id}'`.
   - `--session` (new detached session): `tmux new-session -d -c <repo-root> -P -F '#{pane_id}'`.
   Capture the server pid via `tmux display-message -p '#{pid}'`. The `-P -F` print-format capture is the authoritative way to learn where the new pane landed (tmux(1); DESIGN.md Sources). Guard the call so a tmux failure aborts before any registration.
6. Launch `claude` in the new pane via `send-keys -l -t <pane-id> "claude"` then a separate `Enter` (send-keys `-l` sends literal keys; `Enter` is sent as a named key, per tmux(1)).
7. Wait for readiness with a bounded `capture-pane` poll. No reliable "TUI ready" signal exists (`pane_current_command` stays `claude` whether booting or idle, per DESIGN.md decision 4), so the poll is a heuristic with a hard time cap: poll `capture-pane -p -t <pane-id>`, strip ANSI escape sequences before matching for a prompt-shaped line, and give up after the cap, proceeding regardless. Name the ceiling in a `leanness:` comment.
8. Seed with a ONE-LINE prompt only: `send-keys -l -t <pane-id> "Read @<handover path> and take over."` then a separate `Enter`. Do NOT paste the multi-line handover body via `send-keys`: embedded newline bytes can submit the TUI early (DESIGN.md decision 5). The one-liner pointing at the file is the robust path; the spawned session reads the file itself.
9. Register the spawned agent: `bash ~/.autocode/autocode/comms/lib/channel.sh register <name> <task>` with the captured `pane` id and `server` pid (the card schema and write live in channel-core; DESIGN.md decision 2). This makes the new session addressable before it finishes booting. Its own `SessionStart` inject hook later resolves itself by `$TMUX_PANE` and drains any queued messages.
10. Print the spawned agent name, its pane id plus display coordinates derived via `tmux display-message -p -t <pane-id>`, and the handover path so the caller can address or attach to it.

Guard every tmux invocation with `has-session` (and skip-not-fail on a missing target where the spawn has already persisted state). All file mutation and registration go through the channel-core subcommands and the handover skill; the spawn skill only sequences them and drives tmux.

### Shim shape

The shim mirrors `plugins/autocode/skills/git-commit/SKILL.md`: frontmatter with `name` and `description`, body a single line `Read through @~/.autocode/autocode/comms/skills/comms-spawn/SKILL.md and execute actions according to the instructions in the file.`, forwarding `$ARGUMENTS`.

## Not in scope

Fire-and-forget: the spawner delegates and returns; there is no completion signal back. The spawned agent is registered and therefore addressable, so the spawner polls on its own terms via `comms-send` (check in) or `comms-agents` (is the pane still alive). Auto report-back (a completion hook plus the spawner's agent name stored in the spawned card) is out of scope for v1 (DESIGN.md decision 5).

## Testing

One runnable bash self-check (assert-based, no framework):

`autocode/comms/skills/comms-spawn/test/smoke.sh`

It covers the two non-tmux-dependent halves of the flow with all tmux calls stubbed:

1. Non-tmux guard: with `$TMUX` (and `$TMUX_PANE`) unset, run the spawn entry and assert a clean refusal (non-fatal exit, one-line message, no files written).
2. Register path: pre-create a handover file at a known path (standing in for the inline handover step), stub tmux to return a fixed pane id and server pid, point the lib at a temp messages dir, run the spawn path, and assert the seed prompt references the handover path and that `<name>/card.md` was written with the stubbed pane, server, and task. Real tmux send-keys/new-window are out of scope; the check validates the capture and file-side register mutations only.
