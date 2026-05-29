# Search o'Clock 🔎🕐

[![tests](https://github.com/waitdeadai/searchoclock/actions/workflows/test.yml/badge.svg)](https://github.com/waitdeadai/searchoclock/actions/workflows/test.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Claude Code hook](https://img.shields.io/badge/Claude%20Code-PostToolUseFailure%20hook-d97757)

> **Your AI ships fixes from before its training cutoff.** It defaults to the old, most-common pattern
> instead of the current API; band-aids the symptom (`--force`, `@ts-ignore`, editing the failing
> test) so the real bug ships; skips the web-search tool that's right there; and burns retry loops on
> the same stale guess. Bigger models don't fix it — they trained on yesterday's code too.

**Search o'Clock** is the *enforced* Claude Code hook that stops this. When a command fails it stamps
**today's date**, researches the fix against **live, dated** sources, recommends the most **durable**
fix (not the fastest patch), and makes an **independent second model agree from the evidence** before
the fix is trusted. Works in Claude Code today — and in [any agentic CLI](https://github.com/waitdeadai/searchoclock-core) via the universal core.

### Sound familiar?
- "Latest" means whatever was true at the model's training cutoff, not today.
- It "fixes" the failing test instead of the bug, or slaps on `--force` / `--legacy-peer-deps` to make the error vanish.
- The docs and web-search tools are right there and it just… doesn't use them, so you babysit it toward the real fix.
- A failed command becomes a retry loop that burns tokens re-running the same stale guess.

### Why the obvious fixes don't work
- A **bigger model** still defaults to the old, most-common pattern.
- **`CLAUDE.md` / system prompts** go stale and get ignored — a prompt is a suggestion; a hook is enforcement (see [WHY.md](WHY.md)).
- An **optional `/command`** doesn't fire when you need it — in-prompt good behavior stops transferring once the model can act.
- **Self-review** invents errors or rubber-stamps — you need a *separate* model, which is the searchoclock validator.

`searchoclock` is a single deterministic Claude Code hook (`searchoclock.sh`, a bash wrapper around a
python3 heredoc; **`bash` + `python3` are the only dependencies**). It registers on **`PostToolUseFailure`**
(primary) and **`PostToolUse`** (defensive) for the **`Bash`** tool. It **never blocks** the agent loop —
it injects context via `hookSpecificOutput.additionalContext`, exits 0, and fails open.

## How it works

A non-zero Bash exit fires **`PostToolUseFailure`**, *not* `PostToolUse` (verified
2026-05-29 against [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)
and [anthropics/claude-code#24908](https://github.com/anthropics/claude-code/issues/24908)).
So that event is the primary trigger and its firing *is* the failure signal — no stderr
guessing. The `PostToolUse` registration is a defensive secondary that self-gates and only
fires on an explicit failure signal (`exit_code != 0`, `is_error`, `interrupted`, or a top-level
`error`), so a *successful* command never triggers it.

On a real failure the hook computes the **current local + UTC date** at runtime (the
[time-anchor](https://github.com/waitdeadai/time-anchor) approach — fresh every fire, never
cached), derives a normalized **error signature**, detects **severity**, finds your active
**goal/scope**, and injects a compact (<10 k char) factual-framed protocol next to the tool
result that tells Claude to research the fix live before acting.

## Methodology: probe all candidates, recommend the most durable fix

searchoclock does not hunt for *a* fix — by default it forces a probe of the **whole realistic
solution space** and recommends the most effective **long-term (SOTA-2026)** fix, not the
fastest patch that makes the red go away.

1. **Enumerate** ≥ `SEARCHOCLOCK_MIN_CANDIDATES` (default 3) distinct candidate fixes — typically:
   upgrade to the release that fixed it; a scoped `overrides`/`constraints` to a *patched*
   transitive version; the maintainer's official codemod/migration; a documented config change;
   a documented workaround.
2. **Research each** against **live, dated** sources — official docs / changelogs / release notes /
   the project's own issue tracker first; blogs and the top-voted Stack Overflow answer last
   (popularity and recency are not durability signals). ≥2 independent current sources per claim,
   each with URL + publish/update date + access date + a `verified-live`/`partially`/`unverified` tag.
3. **Score each** on a durability rubric: addresses **root cause** (non-reproducible by the same
   trigger), uses the maintainers' **supported & forward-compatible** path (within ~2 major releases
   of current), is **not EOL/deprecated**, doesn't weaken **security**, minimizes **maintenance burden
   & blast radius**, and is **reversible + lockable by a regression test**. Brittle signals (`--force`,
   `--legacy-peer-deps`, `--no-verify`, blanket pins/downgrades, `eslint-disable`/`@ts-ignore`,
   hand-edited lockfiles, `FROM :latest`) count against a candidate and are acceptable only as a
   commented, ticket-tracked, narrow, time-boxed bridge.
4. **Recommend** the highest-durability candidate that also reproduces on a **clean checkout / frozen
   lockfile** (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --frozen`, `cargo build --locked`,
   committed `go.sum`) — passing tests alone is provably gameable. The fastest **stop-gap** is reported
   separately, and brittle hacks are flagged.

**High-severity escalation** (repeated or high-risk failures): searchoclock spawns **one researcher
per candidate in parallel** plus an **independent judge/verifier** that compares the full candidate
set at once (generative-selection / pairwise) and runs an adversarial "try to break the chosen fix"
pass before anything is applied. The judge is always external to the generators.

*Rubric informed by these sources (accessed 2026-05-29):* Google SRE postmortem culture (mitigate vs prevent);
GOV.UK "keeping software current" (within two major releases; never run EOL; patch fast, 2025-03-19);
Node.js EOL guidance (2025-06-06); "Pinning Is Futile" (FSE 2025) on reflexive dependency pinning;
typescript-eslint on `@ts-ignore`/`any`.

## Install

**As a plugin (recommended):**

```bash
/plugin marketplace add waitdeadai/searchoclock     # or:  /plugin marketplace add ./   (local checkout)
/plugin install searchoclock@searchoclock
```

Hooks activate automatically once the plugin is enabled. Validate before publishing with
`claude plugin validate . --strict`. After a mid-session update, run `/reload-plugins`.

> **Do not** set `disableAllHooks` during a `/goal` run — searchoclock is designed to *coexist*
> with `/goal` and scope troubleshooting to your goal.

**Manual (no plugin system):** copy `searchoclock.sh` to `.claude/hooks/searchoclock.sh`,
`chmod +x` it, and merge [`settings.example.json`](settings.example.json) into your
`.claude/settings.json`.

## What fires it — and what stays silent

| Situation | Result |
|---|---|
| `PostToolUseFailure` for a Bash command (non-zero exit) | **fires** (primary — this is where real Bash failures arrive) |
| `PostToolUse` Bash carrying an explicit error flag (`interrupted`/`is_error`) or an opt-in `SEARCHOCLOCK_FAILURE_PATTERN` match | **fires** (defensive only; ordinary non-zero exits go to `PostToolUseFailure`, not here) |
| Successful command (incl. `git pull` "Already up to date.", `git clone` progress, pip/npm `WARNING`/`DEPRECATION`, `curl` progress) | silent — stderr text is **never** treated as failure |
| `curl`/`wget`/`grep`/`ls`/`WebSearch`/`--version`/… (research & inspection commands) | silent — self-exclusion / loop guard |
| Same error signature again within the cooldown, mid-research window, or over the session budget | silent — dedup & rate guards |
| Non-Bash tool, empty/garbage stdin, `SEARCHOCLOCK_ENABLE=0` | silent |

## Posture: reactive by default, proactive by exception

SOTA-currency isn't a mode you turn on; it's the floor you stand on. You don't have to start a project
aiming for state-of-the-art — searchoclock just makes sure that when something fails (or you're about to
do something risky), you find out fast whether the ecosystem moved on without you. **No dev and no
project is ever forced into deep research.** Three tiers, depth earned by need:

| Tier | What | Default |
|---|---|---|
| **0 · Reactive** | On a Bash failure, inject date-anchored research + durable-fix selection (cheap, deterministic, ignorable). | **on** |
| **1 · Proactive pre-flight** | Before a *risky/version-sensitive* command, a one-shot "verify the current approach" nudge — only on that narrow slice, never every command. | **off** (`SEARCHOCLOCK_PROACTIVE=1`) — see [docs/PROACTIVE.md](docs/PROACTIVE.md) |
| **2 · Deep research** | Multi-candidate probe + parallel researchers + independent judge — auto-escalated on high severity, or explicit via `/searchoclock`. | severity-gated / opt-in |

It's spell-check for staleness, not a research assistant you have to manage: off-switch is one flag,
pre-flight is off by default, and deep mode never fires without a reason or your say-so.

### Works in Opus 4.8 dynamic workflows
searchoclock is **concurrency-safe** for background/parallel agents (per-agent state buckets + a
cross-agent ceiling), so a failure inside a workflow subagent is handled without sibling agents starving
each other. Workflow mode needs `WebSearch`/`WebFetch`/the subagents pre-allowed in `permissions.allow`
(in `settings.example.json`). Full notes + the firing-probe in [docs/WORKFLOW-MODE.md](docs/WORKFLOW-MODE.md).

### Q·T·R scorecard (opt-in)
With `SEARCHOCLOCK_SCORECARD=1` (auto-on for high-stakes fixes), the independent validator emits a
one-line **`SOC SCORE  Q4 · T5 · R3  [gate: PASS]`** — **Q**uality (does it actually + durably resolve,
execution-first), **T**ruthfulness (claims supported/corroborated, execution > citation), **R**elevance
(on-target for *this* exact error/version) — so you see *why* a fix was trusted, not on faith.

## Inter-agent & goal-aware

- **Inter-agent:** the injected protocol tells Claude to dispatch the bundled
  `searchoclock:searchoclock-researcher` subagent (clean context) to do the research and return a
  cited, ranked result. High-severity → one researcher per candidate + an independent judge. Run
  `/searchoclock` to trigger the same researcher on demand (it reads `.searchoclock/last-error.md`).
- **Goal-aware:** searchoclock scopes research to your current objective. It detects an active
  [claudemax](https://github.com/waitdeadai/claudemax) `SPEC.md` (repo root or
  `.claudemax/state/agent-teams-*/`) and tells the researcher to **stay in scope** — no rabbit-holing.
  With no goal detected it falls back to "keep the fix minimal and local."

## Standalone vs claudemax-enhanced

Works with **zero dependencies** beyond Claude Code + `bash` + `python3`: the hook fires, injects the
date-aware protocol, dispatches the researcher, dedups/cooldowns via a local state file, and degrades
goal-scope to the minimal-fix default. It **auto-enhances** when present (all optional, all
graceful-if-absent): reads `SPEC.md` / `.claudemax/state/…` for goal scope; may read/record fixes in
`.claudemax/memory.sqlite` (`errors_solutions`); respects `plan-detection.json` credit budget before
fanning out a team; and its "cite dated sources / flag brittle hacks" protocol is reinforced for free
by the sibling `llm-dark-patterns` honesty hooks.

## Configuration (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `SEARCHOCLOCK_ENABLE` | `1` | Master kill switch. |
| `SEARCHOCLOCK_SOLUTION_MODE` | `durable` | `durable` (probe-all, long-term pick) / `fast` (single verified stop-gap) / `both`. |
| `SEARCHOCLOCK_MIN_CANDIDATES` | `3` | Minimum candidate fixes enumerated & scored (clamped 1–7). |
| `SEARCHOCLOCK_PROBE_ALL` | `1` | `1` forces multi-candidate probing + durability ranking; `0` = legacy single-fix flow. |
| `SEARCHOCLOCK_VALIDATE` | `1` | Require an **independent second model** to agree (from the raw evidence) before a fix is trusted. |
| `SEARCHOCLOCK_VALIDATOR_MODEL` | `claude-haiku-4-5-20251001` | The independent verifier model (Haiku 4.5). |
| `SEARCHOCLOCK_VALIDATE_MIN_CONFIDENCE` | `4` | Integer (1–5) trust floor for the validator verdict. |
| `SEARCHOCLOCK_VALIDATOR_CROSS_PROVIDER` | *(unset)* | Non-Anthropic verifier id for security/irreversible fixes (same-family agreement is correlated). |
| `SEARCHOCLOCK_PROACTIVE` | `0` | Enable the opt-in `PreToolUse` pre-flight nudge (selective; see [docs/PROACTIVE.md](docs/PROACTIVE.md)). |
| `SEARCHOCLOCK_PROACTIVE_GUARD` | `off` | `off`/`ask`/`deny` for destructive commands (never blocks unless `ask`/`deny`). |
| `SEARCHOCLOCK_PROACTIVE_TRIGGERS` | `dep,destructive,version` | Which pre-flight trigger classes are armed. |
| `SEARCHOCLOCK_SCORECARD` | `0` | Emit the Q·T·R (quality/truthfulness/relevance) scorecard from the validator. |
| `SEARCHOCLOCK_MAX_GLOBAL` | `24` | Cross-agent injection ceiling for dynamic-workflow concurrency. |
| `SEARCHOCLOCK_WORKFLOW_TEAM_SIZE` | `2` | High-severity fan-out when running inside a workflow/subagent. |
| `SEARCHOCLOCK_COOLDOWN_SEC` | `900` | Per-error-signature dedup window. |
| `SEARCHOCLOCK_MIN_INTERVAL_SEC` | `60` | Global minimum gap between injections. |
| `SEARCHOCLOCK_MAX_PER_SESSION` | `8` | Hard ceiling of injections per session. |
| `SEARCHOCLOCK_RESEARCH_WINDOW_SEC` | `600` | After firing, suppress further fires (Claude is presumed researching). |
| `SEARCHOCLOCK_REPEAT_ESCALATE` | `2` | Re-occurrences of a signature that escalate severity to `high`. |
| `SEARCHOCLOCK_SEVERITY_MIN` | `low` | Minimum severity to inject (`low`/`medium`/`high`). |
| `SEARCHOCLOCK_TEAM_SIZE` | `3` | Parallel researchers suggested for high severity (max 5). |
| `SEARCHOCLOCK_GOAL_SCOPE` | `auto` | `auto` / `off` / a literal scope string. |
| `SEARCHOCLOCK_STATE_DIR` | `$CLAUDE_PROJECT_DIR/.searchoclock` | State + `last-error.md` location. |
| `SEARCHOCLOCK_IGNORE_CMD_PATTERN` | *(built-ins)* | Extra regex of commands to never troubleshoot. |

## Caveats (read before relying on it)

- **`additionalContext` biases, it does not force.** It strongly nudges Claude to research, but tool
  use is the model's choice. Pre-allow the web tools to remove friction:
  `"permissions": { "allow": ["WebSearch", "WebFetch(domain:*)"] }`.
- **Confirm the trigger on *your* CLI.** The exact `PostToolUseFailure` stdin field names aren't in
  public docs ([#19372](https://github.com/anthropics/claude-code/issues/19372)) — the script reads
  them defensively. There is also an open report ([#55889](https://github.com/anthropics/claude-code/issues/55889))
  that context-injection can be dropped for the Bash matcher on some versions. Dump one real failure
  payload and confirm the protocol appears; if injection is dropped, the `/searchoclock` command is the
  reliable fallback. Verified against CLI **2.1.156** (latest) / **2.1.154** (Opus 4.8 wave).
- **Scope:** only **Bash** failures reliably fire failure hooks; `Read`/`Edit`/`Grep` tool errors do
  not (#24908), so searchoclock is intentionally Bash-only.
- **`--resume`:** injected `additionalContext` is replayed, not re-run, so the embedded timestamp
  reflects when the error occurred (pair with `time-anchor` for a fresh per-session date anchor).

## Sister tools

Part of the [waitdeadai](https://github.com/waitdeadai) Claude Code hook family:
[`time-anchor`](https://github.com/waitdeadai/time-anchor) (the date anchor searchoclock builds on),
[`no-sycophancy`](https://github.com/waitdeadai/no-sycophancy),
[`no-fake-cite`](https://github.com/waitdeadai/no-fake-cite),
[`llm-dark-patterns`](https://github.com/waitdeadai/llm-dark-patterns).

## License

Apache-2.0. See [LICENSE](LICENSE).
