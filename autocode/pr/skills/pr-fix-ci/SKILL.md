# PR fix CI

Diagnose failing CI checks and apply minimal fixes.

## Args

`[PR number]` (default: detect from current branch).

## Workflow

1. Resolve PR (arg or `provider/run.sh git-remote pr-view --json number`).
2. List checks: `provider/run.sh ci pr-check-list <pr>`. If all green, report and stop.
3. For each failing check:
   - Fetch the failure log: `provider/run.sh ci run-view-failed <run-id>`. The script already caps to the last 200 lines of the failing step.
   - Diagnose: classify as lint / build / test / workflow. Read the source or config files referenced in the failure.
4. Apply the minimal fix.
5. Verify locally: read the verify command from `$AUTOCODE_CONFIG_DIR/conventions/build.md`. Run it. If the convention file is missing, stop and instruct the user to run `/autocode-setup`. Do not infer the command from `package.json` or `Makefile`; if the convention says nothing, halt.
6. Delegate commit to `git-commit` (handles push too if upstream tracks).
7. Watch CI start: `provider/run.sh ci run-list --branch <branch> --limit 1`. Report.

## Rules

- Don't skip local verification before pushing.
- One commit per logical fix (group lint fixes together, but separate from test fixes).
- If a failure is not branch-caused (flaky network, infra outage), report and stop. Don't guess at a fix.
- Never `--no-verify`.

$ARGUMENTS
