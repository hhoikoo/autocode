# Handover

Compose a self-contained takeover prompt for a fresh Claude session.

## Args

Optional task description. Default: current conversation's work.

## Workflow

1. Create a temp file via:
   ```bash
   dir=$(mktemp -d -t autocode-handover)
   path="$dir/handover.md"
   ```
   Use `mktemp -d` then append `handover.md`. Do not pass `mktemp -t <name>.md` directly: `mktemp` appends `.XXXXXX` and strips the extension.
2. Compose a self-contained takeover prompt with these sections:
   - `## Context`: what the user wants and why. Include the user-facing goal, not the technical task alone.
   - `## Done`: what's been implemented, decided, or verified so far.
   - `## Remaining`: open work, ordered.
   - `## Troubleshooting`: known gotchas hit during this session.
   - `## Pointers`: file paths, commit SHAs, PR numbers, ticket ids, related design docs.
3. Write the composed prompt to `"$path"`.
4. Print the path. Suggest the user run `claude -p < <path>` or paste into a fresh session.

## Rules

- Self-contained. The takeover prompt must work without any context from this conversation.
- Include explicit paths, SHAs, and IDs. Never "the file we edited" or "the PR".
- Capture troubleshooting only if the gotcha is non-obvious and likely to recur.
- Concise voice. The output prompt itself follows the concise output style.

$ARGUMENTS
