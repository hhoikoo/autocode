# Issue create

Create a tracker issue. Two modes: structured (flags) and interactive (free text).

## Args

```
[-t <type>] [-s <summary>] [-b <body-file>] [-P <parent>]
[-S <points>] [-l <label>]... [-g <repo>] [free-text description]
```

## Workflow

1. If any flag (`-t`, `-s`, `-b`, `-P`, `-S`, `-l`, `-g`) is present, treat as STRUCTURED mode: forward args to `provider/run.sh issue-tracker issue-create [args]` verbatim and report the returned issue number. No prompts.
2. Otherwise INTERACTIVE mode (free-text only, or no args):
   a. If no free text provided, ask via `AskUserQuestion` for a short description.
   b. Briefly research the codebase to ground the issue (Glob/Grep/Read relevant files; ~3-5 reads).
   c. Read `$AUTOCODE_CONFIG_DIR/conventions/issue-types.md` to discover the available types; propose a type and title via `AskUserQuestion`.
   d. Draft a body with sections: `## Summary`, `## Description`, `## Acceptance Criteria`, `## Technical Notes`. Keep each section short; cite specific files when grounded by research.
   e. Confirm the proposed title, type, and body via `AskUserQuestion` (use option preview to show body).
   f. Create the temp file: `dir=$(mktemp -d -t autocode-issue); body_path="$dir/body.md"`. Write body.
   g. Derive assignee: run `provider/run.sh issue-tracker current-user` and use `.login`.
   h. Call `provider/run.sh issue-tracker issue-create -t <type> -s "<title>" -b "$body_path" -a <login>` and capture the issue number from stdout.
   i. Report the created issue key and url-or-pointer to the user.

## Rules

- Repo detection: `gh repo view --json nameWithOwner` if needed; defer to provider scripts to figure out their own context.
- Don't hardcode the type list. Read it from the convention.
- Never invent a `-P <parent>` value; parent is supplied only when the user provides it.
- $ARGUMENTS may be empty.

$ARGUMENTS
