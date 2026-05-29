# Gemini CLI adapter (native hook, v0.26.0+)

Gemini CLI supports hooks bundled inside an **Extension** (commands + context + MCP + hooks). Add a
`PostToolUse`/`AfterTool` hook that calls `socx hook` and inject its stdout as context.

Sketch (confirm exact schema against https://geminicli.com/docs/hooks, 2026):
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "run_shell_command",
        "command": "socx", "args": ["hook"],
        "env": { "SOCX_HARNESS": "gemini-cli" } }
    ]
  }
}
```
Map Gemini's tool payload → the normalized event (`command`, `exit_code`, `stdout`, `stderr`). If the
exact field names differ, add a tiny shim that emits the normalized JSON before piping to `socx hook`.
Until confirmed on your version, the `shell-wrapper` (`socx-run`) is the guaranteed path.
