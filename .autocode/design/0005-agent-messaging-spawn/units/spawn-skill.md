---
depends-on: [channel-core, presence-skills]
type: task
---

# Spawn skill launches a seeded agent in a tmux window

## Summary

One user-facing skill, `a2a-spawn`, that delegates a side task to a fresh Claude session. It reuses the handover skill to produce a self-contained takeover prompt, creates a tmux target (a new window by default or a detached session with `--session`), launches `claude` there, seeds it with a one-line read prompt pointing at the handover file, then registers the new agent in the channel so it is immediately addressable. The skill sources the channel-core lib for dir resolution and registration and reuses the handover and presence register logic rather than reimplementing either. Every tmux call is guarded by `has-session`; outside tmux the skill refuses with a one-line message. The new session resolves its own identity from `$TMUX_PANE` via the channel-core SessionStart inject hook once it boots.

## Implementation

Two files, one skill pair. Real file is body-only (no frontmatter). The shim carries only `name`+`description` frontmatter and a single `@~/.autocode/...` read line. Skill name `a2a-spawn` is globally unique (`a2a-` prefix; not used by any existing feature-set).

Real skill:

- `autocode/comms/skills/a2a-spawn/SKILL.md`

Shim:

- `plugins/autocode/skills/a2a-spawn/SKILL.md`

### a2a-spawn

Delegate a task to a new seeded Claude session in tmux. Workflow:

1. Parse `$ARGUMENTS`: a required task description, an optional `--session` flag (new detached session instead of a new window in the current session), and an optional target agent name. Default the name from the new tmux coordinates when not supplied, matching the presence register default scheme.
2. Guard: if `$TMUX_PANE` is unset (not inside tmux), report a one-line refusal and stop. Spawned agents bind identity to a tmux pane, so the spawner must itself run in tmux.
3. Source the channel-core lib (`autocode/comms/lib/`) for messages-dir resolution and the register helper. Resolve the main-worktree messages dir up front.
4. Invoke the handover skill (`autocode/util/skills/handover`), forwarding the task description. Capture the printed `handover.md` path from its stdout. Do not reimplement handover.
5. Create the tmux target and capture coordinates in one step, setting the working dir with `-c` so the child `claude` boots in the right repo (default the main-worktree root from the lib; new windows otherwise inherit the spawner's cwd, which may be a linked worktree):
   - default (new window in current session): `tmux new-window -c <repo-root> -P -F '#{session_name}:#{window_index}.#{pane_index}'` plus `#{pane_id}` for the stable identity handle.
   - `--session` (new detached session): `tmux new-session -d -c <repo-root> -P -F '#{session_name}:#{window_index}.#{pane_index}'` (and `#{pane_id}`).
   The `-P -F` print-format capture is the authoritative way to learn where the new window/session landed (tmux(1); DESIGN.md Sources). Guard the call so a tmux failure aborts before any registration.
6. Launch `claude` in the new pane via `send-keys -l "claude"` then a separate `Enter` (send-keys `-l` sends literal keys; `Enter` is sent as a named key, per tmux(1) in DESIGN.md Sources).
7. Wait for readiness with a bounded `capture-pane` poll. No reliable "TUI ready" signal exists (`pane_current_command` stays `claude` whether booting or idle, per DESIGN.md decision 4), so the poll is a heuristic with a hard time cap: poll `capture-pane -p -t <pane>` for a prompt-shaped line and give up after the cap, proceeding regardless. Name the ceiling in a `leanness:` comment.
8. Seed with a ONE-LINE prompt only: `send-keys -l -t <pane> "Read @<handover path> and take over."` then a separate `Enter`. Do NOT paste the multi-line handover body via `send-keys`: embedded newline bytes can submit the TUI early (DESIGN.md decision 5). The one-liner pointing at the file is the robust path; the spawned session reads the file itself.
9. Register the spawned agent: reuse the presence register logic (channel-core lib register helper) to write `<name>.md` with the captured `tmux` coords, `pane` id, `repo`, and `task`. This makes the new session addressable before it finishes booting. Its own `SessionStart` inject hook later resolves itself by `$TMUX_PANE` and drains any queued messages.
10. Print the spawned agent name, tmux coords, and handover path so the caller can address or attach to it.

Guard every tmux invocation with `has-session` (and skip-not-fail on a missing target where the spawn has already persisted state). All file mutation, dir resolution, and registration go through the channel-core lib and the handover/register skills; the spawn skill only sequences them and drives tmux.

### Shim shape

The shim mirrors `plugins/autocode/skills/git-commit/SKILL.md`: frontmatter with `name` and `description`, body a single line `Read through @~/.autocode/autocode/comms/skills/a2a-spawn/SKILL.md and execute actions according to the instructions in the file.`, forwarding `$ARGUMENTS`.

## Testing

One runnable bash self-check (assert-based, no framework):

`autocode/comms/skills/a2a-spawn/test/smoke.sh`

It covers the two non-tmux-dependent halves of the flow with all tmux calls stubbed:

1. Non-tmux guard: with `$TMUX` (and `$TMUX_PANE`) unset, run the spawn entry and assert a clean refusal (non-fatal exit, one-line message, no files written).
2. Handover-capture + register: stub the handover step to emit a known `handover.md` path on stdout and stub tmux to return fixed coordinates, point the lib at a temp messages dir, run the spawn path, and assert the seed prompt references the captured handover path and that `<name>.md` was written with the stubbed tmux coords, pane, repo, and task. Real tmux send-keys/new-window are out of scope; the check validates the path-capture and file-side register mutations only.
