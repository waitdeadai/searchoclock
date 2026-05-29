# MCP adapter — `research-on-failure` (supplement, not a guarantee)

MCP is the one extension standard present across almost every agentic harness — but it is
**model-elective**: the model *chooses* to call the tool. That makes it a great *supplement* and a
poor *guarantee*. Use a native hook or `socx-run` for guaranteed-on-failure interception; add this MCP
tool so the agent can also pull date-aware research on demand.

## Tool contract
- **name:** `research_on_failure`
- **input:** `{ command: string, error: string, exit_code?: number, cwd?: string }`
- **behavior:** builds the normalized event, calls `socx hook`, returns the protocol text as the tool result.

## Minimal server (stdio)
A thin wrapper over `socx` — any MCP SDK works. Pseudocode:
```
on call research_on_failure(args):
    event = json({hook_event_name:"command.failed", tool_name:"shell",
                  command:args.command, error:args.error, exit_code:args.exit_code})
    return run(["socx","hook"], stdin=event).stdout   # the protocol text
```
Register it in your harness's MCP config (e.g. `mcpServers`). Set `SOCX_HARNESS` to your harness name.

> A full, packaged MCP server (Python/TS) is a good first community contribution — keep it a pure
> pass-through to `socx` so the protocol/rubric/validation never diverge from the core.
