# Receipts

Reproducible local tests for `searchoclock.sh`. The hook never blocks (always exits 0); it
either prints a JSON `hookSpecificOutput.additionalContext` payload (**fires**) or prints
nothing (**silent**). Every claim below is reproducible with the commands shown.

## Setup

```bash
git clone https://github.com/waitdeadai/searchoclock
cd searchoclock
chmod +x searchoclock.sh
export S="$(mktemp -d)"   # isolated state dir so cooldown/dedup don't bleed across tests
```

`python3` is the only dependency. Each test pipes a hook stdin JSON payload to the script.

### Test 1 — a real Bash failure fires

```bash
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm run build"},"tool_response":{"stderr":"Error: Cannot find module vite"},"exit_code":1}' \
  | SEARCHOCLOCK_STATE_DIR="$S/t1" ./searchoclock.sh hook | python3 -m json.tool
```

Expected: a JSON object with `hookSpecificOutput.hookEventName = "PostToolUseFailure"`, an
`additionalContext` string beginning `SEARCH O'CLOCK …`, and `"suppressOutput": true`.

### Test 1b — the real `PostToolUseFailure` shape (top-level `error`, no `tool_response`)

The documented `PostToolUseFailure` payload carries the error in a top-level `error` string and
has no `tool_response`/`exit_code`. The hook fires on the event and uses that `error` as the excerpt:

```bash
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm run build"},"tool_use_id":"x","error":"npm ERR! build failed: Cannot find module vite"}' \
  | SEARCHOCLOCK_STATE_DIR="$S/t1b" ./searchoclock.sh hook | python3 -m json.tool
```

Expected: fires; `additionalContext` contains the `Cannot find module vite` excerpt.

### Test 2 — a successful command is silent (benign stderr is not failure)

```bash
printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"git pull"},"tool_response":{"stdout":"Already up to date.","stderr":""}}' \
  | SEARCHOCLOCK_STATE_DIR="$S/t2" ./searchoclock.sh hook
# (no output)
```

`git clone` progress on stderr and `pip`/`npm` `WARNING`/`DEPRECATION` notices are likewise silent.

### Test 3 — self-exclusion / loop guard (a failed `curl` does not trigger research)

```bash
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"curl https://x/y"},"tool_response":{"stderr":"curl: (22)"},"exit_code":22}' \
  | SEARCHOCLOCK_STATE_DIR="$S/t3" ./searchoclock.sh hook
# (no output — curl/wget/grep/ls/WebSearch/--version/… are never troubleshooted)
```

### Test 4 — dedup + cooldown

```bash
P='{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm run build"},"tool_response":{"stderr":"Error: Cannot find module vite"},"exit_code":1}'
printf '%s' "$P" | env SEARCHOCLOCK_RESEARCH_WINDOW_SEC=0 SEARCHOCLOCK_MIN_INTERVAL_SEC=0 SEARCHOCLOCK_STATE_DIR="$S/t4" ./searchoclock.sh hook >/dev/null   # fires
printf '%s' "$P" | env SEARCHOCLOCK_RESEARCH_WINDOW_SEC=0 SEARCHOCLOCK_MIN_INTERVAL_SEC=0 SEARCHOCLOCK_STATE_DIR="$S/t4" ./searchoclock.sh hook              # silent (same signature, within cooldown)
```

A *different* error signature fires; the same one within `SEARCHOCLOCK_COOLDOWN_SEC` (default 900s) is suppressed.

### Test 5 — non-Bash, kill switch, empty stdin

```bash
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Edit","error":"x"}' | SEARCHOCLOCK_STATE_DIR="$S/t5a" ./searchoclock.sh hook   # silent (Bash-only)
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","exit_code":1}' | SEARCHOCLOCK_ENABLE=0 SEARCHOCLOCK_STATE_DIR="$S/t5b" ./searchoclock.sh hook   # silent (kill switch)
printf '' | SEARCHOCLOCK_STATE_DIR="$S/t5c" ./searchoclock.sh hook   # silent (no crash)
```

### Test 6 — modes & debug

```bash
echo '{}' | ./searchoclock.sh text     # renders the protocol with a demo error
echo '{}' | ./searchoclock.sh json     # prints {signature, severity, goal_context, now_local, additionalContext_len, …}

# fast mode returns a single fix (no "Enumerate"); durable mode probes candidates
printf '%s' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"npm run build"},"tool_response":{"stderr":"err"},"exit_code":1}' \
  | SEARCHOCLOCK_SOLUTION_MODE=fast SEARCHOCLOCK_STATE_DIR="$S/t6" ./searchoclock.sh hook | python3 -m json.tool
```

## Summary

| # | Scenario | Expected | Exit |
|---|---|---|---|
| 1 | `PostToolUseFailure` Bash non-zero | fires (valid JSON `additionalContext`) | 0 |
| 2 | `PostToolUse` success / benign stderr | silent | 0 |
| 3 | failed `curl`/inspection command | silent (self-exclusion) | 0 |
| 4 | same signature within cooldown | first fires, repeat silent | 0 |
| 5 | non-Bash / `ENABLE=0` / empty stdin | silent, no crash | 0 |
| 6 | `text`/`json` modes, `fast` vs `durable` | renders; fast omits "Enumerate" | 0 |

## Real receipt

Verified on this machine on **2026-05-29** (CLI `2.1.154`, Python `3.12.3`, jq `1.7`):

- `bash -n searchoclock.sh` → clean.
- Fixture battery (all scenarios above, isolated `SEARCHOCLOCK_STATE_DIR` per case): **all matched expectations** — both the `tool_response` shape and the real top-level-`error` shape fired with valid JSON (`event = PostToolUseFailure`, `suppressOutput = true`, contains the `SEARCH O'CLOCK` marker); successes, benign stderr, self-exclusion, non-Bash, kill switch, and empty stdin all silent; cooldown suppressed the same-signature repeat while a new signature fired; a new high-severity signature bypassed the research window.
- Placeholder audit on a fired payload: **no unresolved `{{…}}`** remained.
- Mode × severity `additionalContext` length stayed **~4.5k–5.6k chars** across durable/fast/both × low/high — all well under the 10 000-char cap (exact counts drift with the CLI version string).
- `fast` mode payload correctly contained "single most reliable" and **not** "Enumerate".
- `state.json` and `last-error.md` were written to the state dir only on a fire.

CI runs the same matrix on every push — see [`.github/workflows/test.yml`](.github/workflows/test.yml).
