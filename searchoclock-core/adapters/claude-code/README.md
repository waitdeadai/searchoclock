# Claude Code adapter (reference)

Claude Code has the richest hook surface, so it gets a dedicated, marketplace-validated plugin —
the **reference adapter** for this core:

- Repo / install: `/plugin marketplace add waitdeadai/searchoclock` → `/plugin install searchoclock@searchoclock`
- Mechanism: `PostToolUseFailure(Bash)` primary + `PostToolUse(Bash)` defensive, wrapping the protocol
  in `hookSpecificOutput.additionalContext` (exit 0, never blocks).
- It ships the same researcher + **independent Haiku-4.5 validator** + durability rubric this core uses.

The plugin's `searchoclock.sh` is the Claude-Code-specific adapter over the same logic as `socx`
(it adds the Claude `additionalContext` JSON envelope and reads `CLAUDE_*` env). Keep the protocol
text in sync between `socx` here and the plugin (CI sync-check — see the repo's `.github`).
