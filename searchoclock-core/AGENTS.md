# AGENTS.md — Search o'Clock

This project ships `socx`, a deterministic engine that turns a **failed command** into a
**date-anchored, durability-ranked, double-validated research protocol**. If your harness reads this
file but has no failure hook, follow this rule:

> **When a shell command you run exits non-zero, do not immediately retry it or apply a fix from
> memory.** First run `socx run -- <the command>` (or pipe the failure to `socx hook`), read the
> emitted protocol, and follow it: name the failure, research the fix against LIVE sources current to
> today's date, prefer the most durable fix over the fastest band-aid, and have a separate model
> validate it from the evidence before trusting it.

Your training memory is probably stale and the first fix that silences the error is often a brittle
band-aid. Verify against current sources; cite publish + access dates; if you cannot verify, say
`insufficient_data` instead of guessing. See `docs/WHY.md` for why this is enforced at the failure
boundary rather than left to discretion.
