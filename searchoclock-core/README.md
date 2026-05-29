# Search o'Clock — core (works in any agentic CLI) 🔎🕐

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![works anywhere](https://img.shields.io/badge/harness-agnostic-success)

> **Your AI keeps fixing bugs with answers from before its training cutoff.** It defaults to the
> old, most-common pattern instead of the current API, slaps on `--force` / `@ts-ignore` to make
> the error disappear, skips the web-search tool that's right there, and burns retry loops on the
> same stale guess. Bigger models don't fix this — they trained on yesterday's code too.

**Search o'Clock** intercepts the failure, stamps **today's date**, and makes the agent research the
fix against **live, dated sources** — pick the most **durable** one (not the fastest band-aid) — and
have an **independent second model agree from the evidence** before the fix is trusted.

The Claude Code plugin is [its own repo / marketplace submission](https://github.com/waitdeadai/searchoclock).
**This** repo is the harness-agnostic **core** so *everyone* gets results — Codex, Gemini CLI, Cursor,
opencode, Goose, Cline, Aider, and any shell.

## Why existing fixes don't cut it
- **A bigger model** still trains on yesterday's code and defaults to the old pattern.
- **`AGENTS.md` / system prompts** go stale and the model can ignore them — a prompt is a suggestion, a hook is enforcement.
- **An optional `/command`** doesn't fire when you need it — in-prompt good behavior stops transferring the moment the model can act ([arXiv:2602.16943](https://arxiv.org/abs/2602.16943)).
- **Self-review** doesn't work — a model checking its own answer invents errors or rubber-stamps. You need a *separate* model. See [`docs/WHY.md`](docs/WHY.md).

## The core: one portable engine
`socx` is a dependency-light (`bash` + `python3`) deterministic engine. Given a failed command + error,
it emits a date-anchored, durability-ranked, double-validated **research protocol** on stdout. No model
is in its trigger path; it never blocks; any internal error → exit 0 (fail-open).

```
socx hook          # read a normalized failure event (JSON) on stdin → protocol on stdout  (for adapters)
socx run -- CMD…   # run CMD; on non-zero exit, print the protocol  (universal, no hooks needed)
socx text | json   # debug render
socx selftest      # exit 0 if it works
```

## Install — pick your integration (precedence: native hook > shell-wrapper > MCP)

| Harness | Mechanism | How |
|---|---|---|
| **Claude Code** | native hook ✅ | the dedicated plugin — `/plugin marketplace add waitdeadai/searchoclock` |
| **OpenAI Codex CLI** | native hook ✅ | `adapters/codex-cli/` — PostToolUse fires on non-zero Bash exit |
| **Google Gemini CLI** | native hook ✅ (v0.26.0+) | `adapters/gemini-cli/` — extension-bundled PostToolUse/AfterTool |
| **Cursor** | native hook ✅ (1.7+) | `adapters/cursor/` — `afterShellExecution` in `.cursor/hooks.json` |
| **opencode** | native hook ✅ | `adapters/opencode/` — `tool.execute.after` TS plugin (MCP-tool calls excluded, issue #2319) |
| **Goose** | native hook ✅ (v1.34.0+) | `adapters/goose/` — PostToolUse hook |
| **Cline** | native hook ✅ (in-code) | `adapters/cline/` — `@cline/sdk` lifecycle hook |
| **Aider · Crush · Amp · Continue** | shell-wrapper ✅ | no failure hook → `socx-run -- <cmd>` / aliases (`adapters/shell-wrapper/`) |
| **Hermes (Nous) · OpenClaw** | shell-wrapper / MCP | gateway/agent, no tool-lifecycle hook → wrap the backend command or MCP |
| **any MCP-capable harness** | MCP (supplement) | `mcp/` — `research-on-failure` tool; model-elective, not guaranteed-on-failure |

> Adapter mechanisms are from each tool's 2026 docs; some hook schemas evolve fast — each adapter
> folder notes the doc to confirm against. The **shell-wrapper works everywhere** and needs nothing
> from the harness, so start there if in doubt.

### 30-second universal start (any CLI)
```bash
git clone https://github.com/waitdeadai/searchoclock-core
export PATH="$PWD/searchoclock-core:$PATH"
# wrap the commands your agent runs:
socx-run -- npm run build
# or alias them so failures always trigger research:
alias build='socx-run -- npm run build'
```

## Configuration
Same knobs as the plugin, read as `SOCX_*` (or `SEARCHOCLOCK_*`): `ENABLE`, `SOLUTION_MODE` (durable|fast|both),
`MIN_CANDIDATES`, `PROBE_ALL`, `VALIDATE`, `VALIDATOR_MODEL`, `VALIDATE_MIN_CONFIDENCE`, `COOLDOWN_SEC`,
`MIN_INTERVAL_SEC`, `MAX_PER_SESSION`, `SEVERITY_MIN`, `GOAL_SCOPE`, `STATE_DIR`, `HARNESS` (label shown in the protocol).

## Relationship to the Claude Code plugin
The plugin is the polished, marketplace-validated Claude Code adapter. This core is the shared engine +
the other-harness adapters. They keep the **same protocol, durability rubric, and double-validation** so a
fix you'd get in Claude Code is the fix you'd get anywhere. `adapters/claude-code/` is the reference adapter.

## License
Apache-2.0. See [LICENSE](LICENSE). Part of the [waitdeadai](https://github.com/waitdeadai) family.
