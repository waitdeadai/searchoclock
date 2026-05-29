# Search o'Clock in dynamic workflows / background agents

Opus 4.8 added **dynamic workflows** (`/workflows`, and `/effort ultracode`) — Claude writes a script
that orchestrates up to 16 concurrent / 1,000 total **subagents** in a background, isolated runtime.
Every Bash failure searchoclock cares about happens *inside a workflow subagent*, not the orchestrating
script. Here's how searchoclock behaves there and what you must set.

## Does the hook fire inside a workflow?
**Inferred yes, not officially confirmed.** searchoclock's trigger is a *session-level* plugin hook
(in `hooks/hooks.json`), not per-agent frontmatter — and the hooks reference nests
`PreToolUse`/`PostToolUse`/`PostToolUseFailure` *inside* `SubagentStart`/`SubagentStop`, so a Bash
failure in a workflow subagent should dispatch the session-level hook. But the workflow runtime is "an
isolated environment, separate from your conversation," which leaves a small chance dispatch differs.

**Verify it once on your CLI (CHANGE-0 probe):** temporarily add this throwaway hook and run a workflow
that fails a Bash command in a subagent (e.g. ask for a workflow that runs `npm run nonexistent`):

```jsonc
// .claude/settings.json (throwaway)
{ "hooks": { "PostToolUseFailure": [ { "matcher": "Bash",
  "hooks": [ { "type": "command", "command": "cat >> /tmp/soc-probe.jsonl" } ] } ] } }
```
If lines land in `/tmp/soc-probe.jsonl`, reactive coverage works in workflow mode — also note which keys
carry `exit_code`/`stderr` and what `session_id`/`agent_type` look like across concurrent agents. If
nothing lands, use `/searchoclock` (reads `.searchoclock/last-error.md`) as the manual fallback.

## What you MUST set for workflow mode
Workflow subagents inherit your **session** tool allowlist and run in `acceptEdits`, but plugin
subagents can't carry `permissionMode` — so the researcher/validator will stall on a mid-run prompt
unless you pre-allow, session-wide (see `settings.example.json`):

```json
"permissions": { "allow": [
  "WebSearch", "WebFetch(domain:*)",
  "Agent(searchoclock:searchoclock-researcher)", "Agent(searchoclock:searchoclock-validator)"
] }
```

## Concurrency safety (built in)
Up to 16 sibling agents can share one `session_id` and one `.searchoclock/state.json`. searchoclock
namespaces state **per agent** (derived from `agent_id`/`agent_type`/… with a stable fallback), so a
busy sibling can't starve another's legitimate failure. A separate cross-agent ceiling
(`SEARCHOCLOCK_MAX_GLOBAL`, default 24) stops an N-agent run from fanning out N×, and high-severity
fan-out drops to `SEARCHOCLOCK_WORKFLOW_TEAM_SIZE` (default 2) inside a workflow. Stale agent buckets
are garbage-collected.

## Caveats
- No mid-run user input in a workflow; only the final answer reaches the session. The agent must act on
  the injected context autonomously and surface the fix (and scorecard) in its final report. For staged
  sign-off, run each stage as its own workflow.
- Hook firing inside the isolated workflow runtime is **partially verified** — run the probe above.
- `additionalContext` can be dropped for the Bash matcher on some CLI versions (#55889); `/searchoclock`
  is the fallback either way.
