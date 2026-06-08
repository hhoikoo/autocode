# PR fix CI

Diagnose failing CI checks and apply minimal fixes.

## Args

`[PR number]` (default: detect from current branch).
- `--auto`: run unattended (no `AskUserQuestion`) and end with a structured result block instead of the human report.

## Workflow

1. Resolve PR (arg or `provider/run.sh git-remote pr-view --json number`).
2. List checks: `provider/run.sh ci pr-check-list <pr>`. Green when every check's `bucket` is `pass` or `skipping`; if so, report and stop. A `pending` bucket means CI is still running, not failing. (Under `--auto`, a `pending` rollup does not halt with prose; it ends the run with the terminal block `ci: "pending"`, `fixed: false`, `needs_human: false`.)
3. For each failing check:
   - Fetch the failure log: `provider/run.sh ci run-view-failed <run-id>`. The script already caps to the last 200 lines of the failing step.
   - Diagnose: classify as lint / build / test / workflow. Read the source or config files referenced in the failure.
4. Apply the minimal fix.
5. Verify locally: read the verify command from `$AUTOCODE_CONFIG_DIR/conventions/build.md`. Run it. If the convention file is missing, stop and instruct the user to run `/autocode-setup`. Do not infer the command from `package.json` or `Makefile`; if the convention says nothing, halt. (Under `--auto`, a missing `build.md` does not stop with the `/autocode-setup` message; it ends the run with the terminal block `needs_human: true`, `reason` naming the missing convention.)
6. Delegate commit to `git-commit` (handles push too if upstream tracks).
7. Watch CI start: `provider/run.sh ci run-list --branch <branch> --limit 1`. Report.

## Rules

- Don't skip local verification before pushing.
- One commit per logical fix (group lint fixes together, but separate from test fixes).
- If a failure is not branch-caused (flaky network, infra outage), report and stop. Don't guess at a fix. (Under `--auto`, instead of stopping with prose, end with the terminal block `needs_human: true`, `reason` describing the flaky/infra cause. Same for a verify failure the skill cannot minimally fix.)
- Never `--no-verify`. This rule holds under `--auto`.

## Terminal step (--auto only)

Under `--auto`, emit the structured result as the skill's terminal output, replacing the step-7 human report:

```
{ pr, fixed: bool, ci: "green" | "red" | "pending", needs_human: bool, reason }
```

`ci`: the post-fix rollup from `provider/run.sh ci pr-check-list` (`green` when every bucket is `pass`/`skipping`, `pending` while running, `red` otherwise). `fixed`: true when a fix was committed and pushed this run. `needs_human`/`reason` per the stops above (`reason` empty/omitted when `needs_human` is false).

$ARGUMENTS
