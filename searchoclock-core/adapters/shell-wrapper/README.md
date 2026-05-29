# Shell-wrapper adapter (universal — works in EVERY harness)

No native hook required. `socx-run` runs your command, and on a non-zero exit prints the
searchoclock protocol to the terminal (where the agent reads it), then exits with the command's
**real** exit code so nothing downstream breaks.

```bash
export PATH="/path/to/searchoclock-core:$PATH"
socx-run -- npm run build
socx-run -- pytest -q
socx-run -- cargo build
```

## Make failures always trigger research (aliases)
Add to the shell your agent uses (`.bashrc`/`.zshrc`, or the harness's startup):

```bash
alias build='socx-run -- npm run build'
alias test='socx-run -- pytest -q'
alias deploy='socx-run -- ./deploy.sh'
# generic catch-all for one-offs:
run() { socx-run -- "$@"; }
```

## Recommended for these harnesses (no failure hook as of 2026)
- **Aider** — has `--test-cmd`/`--lint-cmd` around its own edits but no general failure hook; wrap the commands you care about with `socx-run`.
- **Crush (charmbracelet)** — only `PreToolUse` exists today; use `socx-run`.
- **Amp (Sourcegraph)** — MCP + Toolboxes, no documented post-tool hook; expose `socx` as a Toolbox script or use `socx-run`.
- **Continue (cn)** — config-driven, no documented failure hook; use the MCP tool or `socx-run`.
- **Hermes (Nous Research)** — general agent, Skills + MCP only; wrap the backend command or use the MCP tool.
- **OpenClaw** — a chat→agent gateway (message hooks, not tool hooks); integrate at the backend agent it drives (use that agent's native hook) or via MCP.

Set `SOCX_HARNESS="<name>"` so the emitted protocol names your harness. All `SOCX_*`/`SEARCHOCLOCK_*`
config knobs apply.
