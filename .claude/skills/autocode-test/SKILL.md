---
name: autocode-test
description: Test in-progress autocode changes inside ~/.autocode/ without polluting it with uncommitted work. Pushes the current feature branch and checks it out inside ~/.autocode/.
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash Read AskUserQuestion
---

# /autocode-test

Local meta-skill (this repo only). Makes in-progress autocode changes available to runtime `~/.autocode/` consumers without copying or symlinking.

## Why

Shims and hooks resolve paths inside `~/.autocode/`. To test changes in the working clone, check out the same commit inside `~/.autocode/`. Using `git switch` keeps it clean and reversible.

## Workflow

### 1. Confirm the working clone is the autocode repo

Run `git rev-parse --show-toplevel` and `git remote get-url origin`. If origin does not look like an autocode remote (`hhoikoo/autocode` or a fork), stop and tell the user this skill only applies inside the autocode repo.

### 2. Confirm the change is on a pushed feature branch

Run `git branch --show-current` to get the current branch. Refuse to operate on `main`.

Run `git rev-parse @{u}` to check the branch tracks a remote. If no upstream is set, ask the user whether to push:

- Yes -> `git push -u origin HEAD`.
- No -> stop.

Run `git log @{u}..HEAD --oneline` to detect unpushed commits. If any are listed, ask before pushing. When a renewed `quick-fix` skill is available, delegate branch+push+PR creation to it.

Run `git status --porcelain` to detect uncommitted changes. If any, stop and tell the user to commit first. Half-pushed state would silently desync `~/.autocode/`.

### 3. Switch ~/.autocode/ onto the feature branch

```
git -C ~/.autocode fetch origin <branch>
git -C ~/.autocode switch -C <branch> origin/<branch>
```

Use `switch -C` so the local branch in `~/.autocode/` is reset to `origin/<branch>` cleanly, even if it previously diverged. `~/.autocode/` never carries edits, so reset is safe.

### 4. Tell the user

Print:

- "Tested branch `<branch>` is checked out in `~/.autocode/`."
- "When you finish testing, switch `~/.autocode/` back: `git -C ~/.autocode switch main`."
- "The `SessionStart` hook will warn if you forget."

### 5. Optional: switch back

If the user says they are done testing, run `git -C ~/.autocode switch main` and confirm.
