---
name: searchoclock
description: Run date-aware deep-research troubleshooting on the last failed command (or a pasted error). Probes the full solution space and recommends the most effective long-term (SOTA) fix with cited, dated sources — dispatched in a forked researcher subagent.
argument-hint: "[paste an error, or leave empty to use the last captured failure]"
context: fork
agent: searchoclock-researcher
allowed-tools: WebSearch, WebFetch, Read, Grep, Glob, Bash
---
You are running date-aware failure troubleshooting. Today's date matters: if you were not told it, run `date -u +%Y-%m-%dT%H:%M:%SZ` via Bash and treat that as NOW. Your pretrained fix is probably stale and the fastest patch is often a band-aid — verify against LIVE sources and aim for the most durable long-term fix.

ERROR TO RESEARCH:
$ARGUMENTS

If the section above is empty, read the last captured failure from `.searchoclock/last-error.md` (the searchoclock hook writes the failed command, error excerpt, ERROR SIGNATURE, SEVERITY, and SCOPE there). If that file does not exist, ask the user to paste the failing command + error, and stop.

Honor the config knobs:
- `SEARCHOCLOCK_SOLUTION_MODE` (durable|fast|both; default **durable**)
- `SEARCHOCLOCK_MIN_CANDIDATES` (default **3**)
- `SEARCHOCLOCK_PROBE_ALL` (default **1**)

In `durable`/`both` mode with `PROBE_ALL=1` you MUST enumerate at least `MIN_CANDIDATES` distinct candidate fixes, research each, and rank them on the durability rubric. In `fast` mode you may return the single fastest verified fix, but must still cite ≥2 dated sources and label any brittle-hack content. Command flags override env for this run: `--fast`, `--durable`, `--candidates N`.

Follow the **searchoclock-researcher** protocol exactly:
1. Name the failure precisely (error class + the specific tool/lib/version, from the lockfile/manifest).
2. Enumerate the candidate fixes (Phase 1) — include at least one "upgrade/forward" and one "minimal/stay-put" option.
3. Research EACH candidate with date/version-qualified `WebSearch`, then `WebFetch` official docs/changelogs/issue trackers first (blogs/Stack Overflow last; popularity ≠ durability). Require ≥2 independent current sources; cite URL + publish/update date + access date (NOW) + a confidence tag.
4. Score each on the durability rubric (root cause / official & forward-compatible / not-EOL-deprecated / security / maintenance & blast radius / reversibility + test); run the reproducibility gate on a clean checkout / frozen lockfile.
5. STAY SCOPED to the SCOPE from `last-error.md` (or, if none, keep the fix minimal and local — no unrelated refactors).
6. For high-severity failures, spawn one researcher PER candidate in parallel and add an INDEPENDENT judge/verifier pass that compares the full candidate set at once (generative-selection / pairwise) and runs an adversarial "try to break the chosen fix" check — the judge is external to the generators, never self-selection.
7. If `.claudemax/memory.sqlite` exists, you MAY check the `errors_solutions` table for a prior fix to this signature first, and record the chosen durable fix afterward.

Return the researcher's RETURN block verbatim (candidate table with per-candidate sources + durability score; the RECOMMENDED durable fix; the fastest STOP-GAP labelled separately; BRITTLE-HACK flags; scope check).

## Double-validation (independent second model)
Unless `SEARCHOCLOCK_VALIDATE=0` or `--no-validate` is passed, then validate the recommended fix before presenting it as adoptable:
1. Build a CLAIM OBJECT — only the literal error + signature, failed command, the proposed change as a concrete diff/command(s), a one-line falsifiable claim, the cited sources WITH their verbatim fetched text (not links), and the reproducibility command. Discard the researcher's prose.
2. Dispatch subagent type `searchoclock:searchoclock-validator` (model `claude-haiku-4-5-20251001`, or `--validator <id>`) with ONLY the claim object + raw evidence + literal error — never the proposer's reasoning. It returns a binary, evidence-quoted JSON verdict.
3. Append a **VALIDATION** block (agree / disagree + quoted evidence + new_risks + integer confidence) and print **ADOPT** only if `agree==true` AND every cited source supports it AND `error_actually_addressed` AND `confidence>=SEARCHOCLOCK_VALIDATE_MIN_CONFIDENCE` (default 4) AND no unmanaged brittle/security risk; otherwise print **ESCALATE — not validated** and either bounce the objections back to the researcher or re-validate with `SEARCHOCLOCK_VALIDATOR_ESCALATE_MODEL`. For security/destructive/irreversible fixes, use a different-provider verifier (`--cross-provider <id>` / `SEARCHOCLOCK_VALIDATOR_CROSS_PROVIDER`) — Haiku and the proposer are the same family, so same-family agreement is correlated, not fully independent. Treat effortless 100% agreement with no quoted evidence as suspect, not approval.

4. When `SEARCHOCLOCK_SCORECARD=1` (auto-on for high-stakes fixes), also print the compact one-line scorecard so the user sees WHY the fix was trusted, e.g. `SOC SCORE  Q4 · T5 · R3   [gate: PASS]   overall=3` with a one-line per-axis rationale (Quality / Truthfulness / Relevance). Ship only if `min(Q,T,R) >= 3` AND `Q >= 4` for high-stakes; otherwise **ESCALATE**.

Flags: `--fast`, `--durable`, `--candidates N`, `--no-validate`, `--validator <model-id>`, `--cross-provider <model-id>`, `--scorecard`.

> Inside an Opus 4.8 **dynamic workflow** there is no mid-run user input and only the final answer reaches the session, so `/searchoclock` is also the reliable manual fallback when in-session injection isn't visible — and for staged sign-off, run each workflow stage as its own workflow.

Do NOT apply the fix yourself — recommend it so the user/main agent can apply it. If no live source confirms a durable fix for the installed version, report `insufficient_data` rather than guessing. No praise, no filler, no emojis.
