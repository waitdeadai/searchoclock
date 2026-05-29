# Goose adapter (native hook, v1.34.0+)

Goose added a `PostToolUse` hook in v1.34.0 (2026-05). Register a hook that calls `socx hook` and
feeds its stdout back as context. Map Goose's tool payload → the normalized event
(`command`, `exit_code`, `stdout`, `stderr`).

Confirm the hook config format + payload against the Goose releases/docs (github.com/aaif-goose/goose,
2026-05) — this hook is newer and less battle-tested than Claude/Codex/Cursor. Set
`SOCX_HARNESS=goose`. Until confirmed on your version, `socx-run` (shell-wrapper) is the guaranteed path.
