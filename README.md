# autocode

A Claude Code plugin that ships opinionated skills, subagents, hooks, and provider scripts for everyday coding work: issues, branches, PRs, and reviews.

## Installation

Add the marketplace and install the plugin:

```bash
claude plugin marketplace add hhoikoo/autocode
claude plugin install autocode
```

From a Claude Code session inside the target repo, run `/autocode-setup`. It:
- clones this repo to `~/.autocode/` (shallow, single-branch, push disabled);
- creates a per-repo config dir (default `<repo>/.autocode/`);
- writes `settings.json` (shared, committed) and `settings.local.json` (per-user, gitignored), and scaffolds `conventions/` there;
- exports `AUTOCODE_CONFIG_DIR` into the appropriate Claude Code settings file.

Run `/autocode-update` to pull the latest. The plugin's `SessionStart` hook warns when `~/.autocode/` is missing, out of date, or on a non-`main` branch.

## Development

```bash
git clone https://github.com/hhoikoo/autocode.git
cd autocode

# Install git hooks and any future repo-init steps
make init

# Launch Claude Code with the local plugin tree loaded
scripts/claude-dev.sh
```

Edit real definitions under `autocode/<feature-set>/` (body only, no frontmatter). Frontmatter lives only in the shim under `plugins/autocode/`. Use the `/autocode-test` skill (see `.claude/skills/autocode-test/`) to test in-progress changes inside `~/.autocode/` without polluting it with uncommitted work.

## Documentation structure

Most documentation lives next to the code it describes, as nested `CLAUDE.md` files. Start at the root `CLAUDE.md` for orientation, then follow the path that matches what you are touching. The shim+source split, voice rules, and verify-before-assuming guidance all live in the root `CLAUDE.md`.
