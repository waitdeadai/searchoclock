# Pre-flight (proactive) mode — opt-in, selective, non-blocking

Reactive troubleshooting fixes the problem after a command fails. **Pre-flight** tries to prevent it:
right before the agent runs a *risky or version-sensitive* command, searchoclock injects a one-shot
"verify the current approach as of today before you write it" nudge. It is **off by default** and fires
only on a narrow slice — not on every command — because not every dev wants deep research on everything.

## Turn it on
```bash
SEARCHOCLOCK_PROACTIVE=1
```
That's it. It registers on **`PreToolUse(Bash)`** and is **non-blocking** by default
(`permissionDecision: allow` + a short `additionalContext` brief). It never blocks unless you opt in.

## Why `PreToolUse`
It's the only lifecycle event that fires **before each individual command** *and* can both inject
context (`additionalContext`) and gate the action (`permissionDecision`). `SessionStart`/`SubagentStart`
can inject but can't see the concrete command; `UserPromptSubmit` fires per-turn before a tool is chosen
(noisier). Pre-action interception is what enables *prevention* rather than only post-failure repair.
> Requires a CLI new enough to support `additionalContext` in `PreToolUse` (≈ v2.1.9+); on older CLIs the
> hook fails open (allow, no context). This machine reports a current 2.1.x.

## What it fires on (selective — `SEARCHOCLOCK_PROACTIVE_TRIGGERS=dep,destructive,version`)
- **dependency** — first touch / install / upgrade of a package (`npm/pnpm/yarn add|install`, `pip/uv add|install`, `cargo add`, `go get`, `brew/apt install`, …). Briefed **once per package per agent**, then silent.
- **destructive** — `rm -rf`, `drop/truncate table`, force-push, `*migrate`, `terraform apply/destroy`, `kubectl delete`, prod deploy, … (on the normalized command, so a wrapper/obfuscation can't hide it).
- **version-sensitive** — fast-moving SDK/framework surfaces or version-pinning/lockfile ops.

Ordinary reads/edits/builds get **nothing** (zero noise). Tune the set, or add ignores with
`SEARCHOCLOCK_IGNORE_CMD_PATTERN`.

## Optional gating for destructive commands
By default destructive commands get a context nudge only (no block). To add friction:
```bash
SEARCHOCLOCK_PROACTIVE_GUARD=ask   # PreToolUse permissionDecision: ask (escalate to you)
SEARCHOCLOCK_PROACTIVE_GUARD=deny  # block with a reason
```
It never uses `allow`-to-widen (a hook can't bypass an explicit deny rule anyway), and it gates on the
deterministic destructive lattice — never on a model confidence guess.

## Cost
The trigger pass is pure regex on the normalized command (no model, no web call) — same latency profile
as the reactive path. The injected brief just *instructs* the agent to verify-before-writing and, only
for a flagged version-sensitive/first-touch surface, optionally dispatch the researcher. Actual research
stays the agent's choice on the narrow flagged slice.

## Posture
Reactive-by-default (cheap, always-on, ignorable) → proactive-by-exception (opt-in, narrow, nudge) →
deep research (opt-in or severity-escalated). No dev and no project is ever forced into deep research.
