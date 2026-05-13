# Build and verify

This repo is a Claude Code plugin (shell scripts, Markdown skills and agents, JSON manifests). Verification is a structural shape check over the plugin layout plus shellcheck on shipped scripts. CI runs the same script.

## Verify command

```bash
make check
```

(Wraps `./scripts/check-plugin-shape.sh`.)

## Notes

- Requires `shellcheck` on PATH; CI installs it via apt. On macOS: `brew install shellcheck`.
- No unit-test suite; the shape check is the canonical verification.
- Fast (seconds). No known flakes.
