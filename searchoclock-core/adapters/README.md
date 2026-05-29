# Adapters

An adapter's only job: translate your harness's native "command failed / post-tool" payload into
socx's **normalized event** and pipe it to `socx hook`, then surface `socx` stdout back into the
agent's context. Precedence: **native hook > shell-wrapper > MCP**.

## Normalized event (what `socx hook` reads on stdin)
```json
{ "hook_event_name": "command.failed | PostToolUseFailure | afterShellExecution | …",
  "tool_name": "Bash | shell | …",
  "command": "<the command>",
  "exit_code": 1, "stdout": "…", "stderr": "…",
  "is_error": false, "interrupted": false, "error": "<top-level error text>",
  "cwd": "<path>", "session_id": "<id>", "date_iso": "<optional override>" }
```
All keys optional; missing → fail-open. socx decides "failure" if the event is a failure event, OR
`exit_code` ∉ {0,null}, OR `is_error`/`interrupted`/`error` is set. Set `SOCX_HARNESS=<name>`.

## Status by harness (mechanisms from each tool's 2026 docs — confirm the schema before shipping)
| Harness | Mechanism | Folder / note |
|---|---|---|
| Claude Code | native hook ✅ | `claude-code/` → the standalone plugin (marketplace submission) |
| OpenAI Codex CLI | native hook ✅ | `codex-cli/hooks.json` — PostToolUse fires on non-zero Bash exit |
| Gemini CLI (0.26.0+) | native hook ✅ | `gemini-cli/` — extension-bundled PostToolUse/AfterTool |
| Cursor (1.7+) | native hook ✅ | `cursor/hooks.json` — `afterShellExecution` |
| opencode | native hook ✅ | `opencode/` — `tool.execute.after` TS plugin (excludes MCP-tool calls, issue #2319) |
| Goose (1.34.0+) | native hook ✅ | `goose/` — PostToolUse hook (newer/less battle-tested) |
| Cline | native hook ✅ | `cline/` — `@cline/sdk` lifecycle hook, registered in code |
| Aider, Crush, Amp, Continue | shell-wrapper ✅ | `shell-wrapper/` — `socx-run` / aliases |
| Hermes (Nous), OpenClaw | shell-wrapper / MCP | wrap the backend command, or `mcp/` |
| any MCP harness | MCP (supplement) | `mcp/` — model-elective, not guaranteed-on-failure |

## Add an adapter
1. Find your harness's post-tool / command-failed hook (or fall back to `shell-wrapper`).
2. Map its payload → the normalized event (a few `jq`/inline lines).
3. `command: socx`, `args: ["hook"]` (or pipe JSON to `socx hook`); set `SOCX_HARNESS`.
4. Route `socx` stdout into the agent's context the way your harness injects context.
5. PRs welcome — include the doc URL you verified the hook schema against and the date.
