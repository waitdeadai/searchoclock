# Portable agent prompts

`searchoclock-researcher.md` and `searchoclock-validator.md` are the same prompts the Claude Code
plugin ships, kept here so non-Claude harnesses can reuse them.

- **Harnesses with a subagent system** (Claude Code, Codex, etc.): register these as subagent
  definitions and let the protocol dispatch them by name.
- **Harnesses without subagents**: paste the prompt bodies inline, or have your single agent follow
  them as a checklist. The `socx` protocol already says "if your harness can dispatch a subagent,
  spawn one; otherwise do this yourself," so a single agent still gets the probe-all + durability +
  double-validation flow.

The **researcher** proposes (untrusted); the **validator** (a separate, cheaper model — default
Haiku 4.5) re-derives the verdict from the claim + raw evidence + literal error only, and must agree
before the fix is trusted. Never let the same model that proposed a fix be the one that validates it.
The frontmatter `model:` lines are Claude-specific; swap them for your harness's model selector.
