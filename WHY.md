# Why this is an *enforced hook*, not an optional command

**Thesis:** a capability that changes whether your agent ships a *correct, current* fix must not be left to the model's discretion. The moment a model can **act** (call tools), its good in-prompt behavior stops transferring to its real behavior — so the trigger has to live one layer *below* the model, in a deterministic hook it cannot skip, edit, or argue away.

This is the difference between **a suggestion and a guarantee**:

> "A system prompt is a natural-language suggestion interpreted by a probabilistic model. It can be overridden by prompt injection, ignored across multi-turn conversations, or simply misinterpreted." Hooks enforce fixed rules *independent of what the model intends to do.* — Obsidian Security, 2026-05-07
>
> "The model determines what it wants to accomplish; the hook determines whether it gets to." — Endor Labs, 2026-05-12

## 1. Tool access breaks compliance
Models that are perfectly compliant in text-only settings show sharp behavior drift once they're *tool-enabled* under identical rules — "text safety does not transfer to tool-call safety." Passing in-prompt safeguards gives false confidence; enforcement has to sit at the **tool-call boundary**. An optional `/searchoclock` the model *should* run is exactly the in-prompt safeguard that doesn't transfer.

*Sources (live, 2026): arXiv:2602.16943 ("text safety does not transfer to tool-call safety"); arXiv:2603.20320 (tool-enabled violation-rate jump). The specific headline percentages in those papers are directional single-testbed figures, not universal rates.*

## 2. Agents skip the lookup that would fix the bug
Even when the right tool is sitting there, agents are documented to *not call it*. Practitioners report agents "regularly skip actually using [the docs/lookup tool] even when it would be appropriate" and "'fix' broken tests by changing the tests" (tedivm, 2026-03). If the lookup that produces a current, durable fix is left to the model's initiative, it will often be skipped — so it must be triggered **out-of-band**.

## 3. The failure boundary is the highest-leverage interception point
A command failure is the moment theoretical intent becomes operational impact. Intercepting *there* — stamping the date and forcing live-verified, independently-validated, durable-fix selection — is the difference between a stale band-aid shipping to prod and a root-cause fix landing the first time.

## 4. The economics of *not* intercepting are severe
Blind retry of a stale fix is the engine of runaway loops. Practitioner reports describe retry/loop amplification pushing token cost well above baseline and documented runaway sessions (a widely-reported ~$47k loop in Nov 2025; multi-billion-token sessions). *These are practitioner-blog figures, corroborated across sources but not vendor-audited — treat as directional.* Deterministic interception plus durable-fix selection at the boundary is the brake.

## 5. So: enforce — but narrowly, deterministically, and fail-open
Enforcement is only safe if it's cheap and can't itself break the loop:

- **The trigger is pure code, no model in the path.** A regex matcher on Bash failures — not an LLM judgment — so there's no self-critique-paradox failure mode and latency is negligible.
- **Narrow matcher.** Bash failures only; benign stderr (clone progress, warnings, "Already up to date") never fires it.
- **Rate/cooldown/budget guards.** Dedup by error signature, one-research-at-a-time window, per-session ceiling — so it can't spam or loop.
- **Fail-open, always.** Any internal error → exit 0, inject nothing. The hook is invisible until a real failure and *never blocks the agent loop*.
- **Two model steps run AFTER the deterministic fire:** research (propose, untrusted) and an **independent second model** (re-validate from the raw evidence). The model can't skip the trigger; the second model can't be the same one that proposed.

> Security note: agent hooks are themselves an execution surface (CVEs have been reported against hook implementations in 2026). Treat the hook config as code: review it, pin versions, and keep it fail-open. Verify any specific CVE ID against NVD before relying on it.

## The one-line version
Trusting a probabilistic model to *remember* to check its work against today's reality is how stale band-aids ship. Put the trigger where the model can't reach it, force live verification, make a **second, independent** model agree before the fix is trusted — and never block the loop if any of that fails.

That's why every serious harness that wants effective, boundary-pushing results should ship this as an **enforced, deterministic, fail-open hook**. See [`README.md`](README.md) for the implementation and the universal (any-CLI) core.
