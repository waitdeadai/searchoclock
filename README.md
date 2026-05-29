# Search o'Clock — marketplace

<p align="center">
  <img src="assets/og.png" alt="Search o'Clock — date-aware, inter-agent error-troubleshooting hook" width="760">
</p>

This repository is a Claude Code **plugin marketplace** containing one plugin:
[`searchoclock`](./searchoclock) — a date-aware, inter-agent error-troubleshooting hook.

> When a command fails, Claude's first instinct is a fix from training memory — which
> is often months or years stale. **Search o'Clock** intercepts the failure, stamps the
> *current* date, and pushes Claude to research the fix against live, dated sources
> (dispatching a dedicated research subagent) before it acts.

## Install

```bash
# From GitHub (once published):
/plugin marketplace add waitdeadai/searchoclock
/plugin install searchoclock@searchoclock

# Or from a local checkout (this repo root contains .claude-plugin/marketplace.json):
/plugin marketplace add ./
/plugin install searchoclock@searchoclock
```

Hooks activate automatically once the plugin is enabled (no separate step).
Validate before publishing:

```bash
claude plugin validate ./searchoclock --strict
```

Prefer not to use the plugin system? `searchoclock` also ships a
[`settings.example.json`](./searchoclock/settings.example.json) for a manual
`.claude/hooks/` install.

## What's in the plugin

| Component | Purpose |
|---|---|
| `searchoclock.sh` | The hook (bash + python3). Fires on a Bash failure, injects date-anchored troubleshooting context. |
| `agents/searchoclock-researcher.md` | The research subagent it dispatches (`searchoclock:searchoclock-researcher`). |
| `commands/searchoclock.md` | `/searchoclock` — run the date-aware researcher on the last/pasted error on demand. |
| `hooks/hooks.json` | Registers `PostToolUseFailure` (primary) + `PostToolUse` (defensive), matcher `Bash`. |

Full documentation, configuration, and the verification ledger live in
[`searchoclock/README.md`](./searchoclock/README.md) and
[`searchoclock/RECEIPTS.md`](./searchoclock/RECEIPTS.md).

## Standalone product

`searchoclock/` is a complete, self-contained plugin and can be lifted into its own
repository (`github.com/waitdeadai/searchoclock`). It works with **zero dependencies**
beyond Claude Code + `python3`, and *auto-enhances* when [claudemax](https://github.com/waitdeadai/claudemax)
or an active `/goal` is detected (it scopes troubleshooting to your current objective).

## License

Apache-2.0. See [LICENSE](./searchoclock/LICENSE).

Part of the [waitdeadai](https://github.com/waitdeadai) Claude Code hook family —
sister tools: [`time-anchor`](https://github.com/waitdeadai/time-anchor),
[`no-sycophancy`](https://github.com/waitdeadai/no-sycophancy),
[`llm-dark-patterns`](https://github.com/waitdeadai/llm-dark-patterns).
