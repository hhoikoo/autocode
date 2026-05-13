# Issue view

Display a single issue in a readable shape.

## Args

`<issue-key>` (e.g. `42`, `#42`, or `BA-1234`). Strip leading `#`.

## Workflow

1. Run `provider/run.sh issue-tracker issue-view <key>` to fetch JSON `{key, summary, description, type, status, parent}`.
2. Parse and pretty-print to the user:
   - `Key: <key>`
   - `Summary: <summary>`
   - `Type: <type>`
   - `Status: <status>`
   - `Parent: <parent>` (omit line entirely if empty)
   - Blank line.
   - `Description:` followed by the full body.

## Rules

- Never edit. This is a read-only viewer.
- If the provider script exits non-zero, surface its stderr to the user and stop.

$ARGUMENTS
