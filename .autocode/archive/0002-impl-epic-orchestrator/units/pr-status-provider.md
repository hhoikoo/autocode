---
depends-on: []
type: task
---

# Normalized PR-status and PR-find provider scripts

## Summary

The orchestrator's monitor needs one typed PR-state call and a unit-to-PR lookup, but the only PR-state surface today is `provider/git-remote/github/pr-view.sh`, a raw `gh pr view "$@"` passthrough with no normalized contract. Scattering raw `gh pr view --json ...` parsing into the orchestrator and monitor would duplicate git-host knowledge and leak it past the provider boundary. This unit adds two `git-remote` provider scripts: `pr-status <pr>` returns one typed JSON object the monitor branches on (state, mergeable, merge-state, CI rollup, review decision, draft, url, number), and `pr-find <issue-key>` maps a unit to its PR number via the PR's `Closes #<key>` link (the branch shortname is a non-reproducible slug, so the issue key is the durable handle; a `--branch` mode is kept as a secondary). Both follow the existing provider script contract (env/positional args, `jq`-built JSON on stdout, stderr progress, `-g <owner/repo>` override) and are reached only through `provider/run.sh git-remote <feature> [args]`.

## Implementation

Two new provider scripts under the existing `git-remote/github` provider, plus a `provider/CLAUDE.md` doc note for the new features. No skill changes; consumers are the monitor unit (`impl-orchestrator-monitor`), which calls these via the dispatcher.

### Files to create

- `provider/git-remote/github/pr-status.sh`
- `provider/git-remote/github/pr-find.sh`

### Files to modify

- `provider/CLAUDE.md`: the `<feature>` examples list is illustrative, not exhaustive (`run.sh` resolves any `<feature>.sh` by name), so no registry edit is strictly required; add `pr-status` and `pr-find` to the git-remote feature examples only if the existing doc enumerates per-provider features. Confirm at implementation time; do not invent a registry that does not exist.

### Plugin shim / settings

None. Provider scripts are not shims (the shim rule in root `CLAUDE.md` and `.claude/rules/prompt-engineering.md` covers skills and agents only); `provider/` has no plugin mirror. No new settings key. No `settings-schema.md` edit: `github` is already a valid `provider.git-remote` value and these are new features of an existing provider, not a new provider (`provider/CLAUDE.md:30-35`).

### `pr-status.sh` contract

```
Usage: pr-status.sh <pr-number> [-g <owner/repo>]
Stdout: one JSON object (typed PR state)
```

Source fields in a single `gh pr view <n> --json state,mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,isDraft,url,number` call (research finding; `reviewDecision` is the native GitHub field carrying `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED`, preferred over re-deriving from raw `reviews`). Normalize via `jq` to:

```json
{
  "number":          <int>,
  "url":             "<string>",
  "state":           "open" | "merged" | "closed",
  "isDraft":         <bool>,
  "mergeable":       "mergeable" | "conflicting" | "unknown",
  "mergeStateStatus":"<gh mergeStateStatus, lowercased>",
  "ci":              "passing" | "failing" | "pending" | "none",
  "reviewDecision":  "approved" | "changes_requested" | "review_required" | "none"
}
```

Normalization rules the implementer owns:

- `state`: lowercase the gh enum (`OPEN`/`MERGED`/`CLOSED`).
- `ci` rollup: derive from `statusCheckRollup`. Reuse the bucket vocabulary already established by `provider/ci/github/pr-check-list.sh:6` (`{name,bucket,state,link,workflow}`): any failing bucket -> `failing`; else any pending/in-progress -> `pending`; all passing -> `passing`; empty rollup -> `none`. Pick whether to compute inline from `statusCheckRollup` or to call `pr-check-list` and roll up; inline keeps it one `gh` call (preferred), but either is acceptable. State the choice in a comment.
- `reviewDecision`: lowercase; GitHub returns empty string when no review is required, map empty -> `none`.
- `mergeable`: lowercase the gh enum (`MERGEABLE`/`CONFLICTING`/`UNKNOWN`).

A merged or closed PR still returns a well-formed object; the monitor uses `state` to short-circuit. This is the single call the monitor branches on per DESIGN.md decision 7 and runtime-flow step 5.

### `pr-find.sh` contract

```
Usage: pr-find.sh <issue-key> [-g <owner/repo>]
       pr-find.sh --branch <branch> [-g <owner/repo>]   # secondary
Stdout: { "number": <int>, "state": "open"|"merged"|"closed" }  on a match
        {} (empty object)                                       on no match
```

Map a unit to its PR by the SUB-ISSUE KEY, the only durable cross-session handle. The branch is NOT a reliable key: `git-create-branch` builds the `<short>` segment as a model-generated slug of the issue summary (`git-create-branch/SKILL.md:34`), so it is not reproducible across sessions and can diverge if the title is edited (research finding). Resolve by the `Closes #<key>` link the PR body already carries (`design-folder.md` lifecycle: `impl-push` writes `Closes #<unit>`): use the GitHub closing-reference link, `gh api graphql` on the issue's `closedByPullRequestsReferences` (or the PR's `closingIssuesReferences`); a `gh pr list --search "in:body #<key>" --state all --json number,state` is an acceptable simpler fallback, eventually-consistent. Keep a secondary `--branch <branch>` mode (`gh pr list --head <branch> --state all`) for callers that already hold an exact branch (e.g. inside a worktree); document it as secondary. On multiple matches, return the first non-closed (the live PR); on none, emit `{}` and exit `0` (absence is not an error, the monitor treats empty as "no PR yet").

### Conventions both scripts follow

Mirror `provider/issue-tracker/github/issue-epic-list.sh:17-45` and `provider/git-remote/github/pr-merge.sh`:

- `#!/usr/bin/env bash` + `set -euo pipefail`; header comment with usage and `Depends on: gh, jq`.
- `gh` presence guard exiting `2` when absent (`issue-epic-list.sh:17-20`).
- Required positional via `:?` guard (`pr-merge.sh:9`); `-g <owner/repo>` parsed in the same arg loop as `issue-epic-list.sh:25-31`, passed to `gh` as `--repo "${owner}/${name}"` when set so the scripts work outside a checkout.
- JSON to stdout via `jq` only; progress/errors to stderr, no ANSI. Exit `0` success, `1` bad input / missing PR-as-error, `2` unexpected (`provider/CLAUDE.md:18-28`).
- `run.sh` already `exec`s any `git-remote/github/<feature>.sh` by name (`provider/run.sh:46-56`); no dispatcher change.

### Tests

DESIGN.md testing strategy calls for "unit-level shell tests with mocked `gh` output (fixture JSON), asserting the normalized shape and the unit->PR mapping; follow the existing `provider/` test conventions." There is no existing `provider/` test harness in the repo (no `provider/**/tests`, no test runner found this session), so "existing conventions" do not exist to follow. Implementer decision, in priority order:

1. Run `shellcheck` on both new scripts (mandated by `provider/CLAUDE.md:35`).
2. Manual fixture check: shim `gh` on `PATH` (a stub printing canned `--json` output) and assert `pr-status.sh` emits each normalized variant: open+passing+approved, conflicting, failing CI, draft, merged, empty rollup; assert `pr-find.sh` returns the live PR on match and `{}` on no match.

If the epic wants a committed test harness, that is a separate concern not scoped to this unit; flag it rather than scaffolding a repo-wide convention here.

```
monitor checker ──> provider/run.sh git-remote pr-find  <issue-key> ──> { number, state }
                └─> provider/run.sh git-remote pr-status <number>    ──> typed PR-state object
                                                                       (state | mergeable | ci | reviewDecision)
```
