# Contributing to Search o'Clock

Thanks for helping. searchoclock is a single, dependency-light Claude Code hook
(`searchoclock.sh`, bash wrapper + a python3 heredoc). The bar is: it must never
break the agent loop (always exit 0), never over-fire, and always anchor research
to the current date.

## Run the fixtures locally

```bash
# Debug renders
echo '{}' | ./searchoclock.sh text     # rendered protocol
echo '{}' | ./searchoclock.sh json     # computed signature/severity/lengths

# A real failure fires; a success stays silent
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm run build"},"tool_response":{"stderr":"Error: Cannot find module x"},"exit_code":1}' \
  | SEARCHOCLOCK_STATE_DIR=/tmp/soc-test ./searchoclock.sh hook | python3 -m json.tool
```

The full matrix runs in CI (`.github/workflows/test.yml`) and is documented in
[`RECEIPTS.md`](RECEIPTS.md). Add a fixture there for any behavior you change.

## Ground rules

- **Fail-open.** Any internal error → exit 0, no output. The hook is invisible until a real failure.
- **No new runtime dependencies.** python3 stdlib + bash only.
- **Date-anchored.** Timestamps come from the local system clock at fire time (`datetime.now().astimezone()`), never hardcoded.
- **Verify time-sensitive claims live.** If you touch anything that depends on the Claude Code hooks API, re-confirm against <https://code.claude.com/docs/en/hooks> and cite the access date.

## Sister tools

searchoclock is part of the [waitdeadai](https://github.com/waitdeadai) Claude Code
hook family — see [`time-anchor`](https://github.com/waitdeadai/time-anchor) (the date
anchor it builds on) and [`llm-dark-patterns`](https://github.com/waitdeadai/llm-dark-patterns).
