#!/usr/bin/env bash
# searchoclock — Search o'Clock
# Claude Code PostToolUseFailure / PostToolUse (Bash) hook.
#
# When a Bash command FAILS, inject date-anchored deep-research troubleshooting
# context so the agent fixes the error against CURRENT (live, dated) sources
# instead of a stale pretrained fix — and dispatch a dedicated research subagent
# (searchoclock:searchoclock-researcher) for clean-context, cited verification.
# Date-aware (sibling of time-anchor), goal-scoped (stays inside an active
# /goal or claudemax SPEC), inter-agent, and fully standalone.
#
# Idiom: bash wrapper + python3 heredoc (time-anchor style). Dependency: python3.
# Output: hookSpecificOutput.additionalContext on stdout, exit 0 (never blocks).
# Fail-open everywhere: any internal error -> exit 0, never break the agent loop.
#
# Apache-2.0 · https://github.com/waitdeadai/searchoclock

set -euo pipefail

COMMAND="${1:-hook}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -d "$PROJECT_DIR" ] || PROJECT_DIR="$(pwd)"

# --- read stdin into a temp file (fail-open on empty / no tty) ---------------
INPUT_FILE="$(mktemp 2>/dev/null || echo /tmp/searchoclock.$$.json)"
cleanup() { rm -f "$INPUT_FILE" 2>/dev/null || true; }
trap cleanup EXIT
if [ -t 0 ]; then
  printf '{}\n' > "$INPUT_FILE"
else
  cat > "$INPUT_FILE" 2>/dev/null || true
  [ -s "$INPUT_FILE" ] || printf '{}\n' > "$INPUT_FILE"
fi

# --- cheap early kill switch (hook mode only; debug modes still render) -------
case "$COMMAND" in
  text|--text|json|--json|test|selftest) : ;;
  *) case "${SEARCHOCLOCK_ENABLE:-1}" in 0|false|False|FALSE|no|NO|off|OFF) exit 0 ;; esac ;;
esac

# --- python3 is required; if absent, fail-open silently ----------------------
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# CLI version is resolved lazily inside python on the fire path only, so a
# `claude --version` subprocess never runs for ordinary (successful) Bash calls.
python3 - "$COMMAND" "$PROJECT_DIR" "$INPUT_FILE" <<'PY' || exit 0
import os, sys, json, re, time, hashlib, glob, tempfile
import datetime as dt

# ----------------------------------------------------------------------------- args
COMMAND     = (sys.argv[1] if len(sys.argv) > 1 else "hook").lower()
PROJECT_DIR = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()
INPUT_FILE  = sys.argv[3] if len(sys.argv) > 3 else ""

def out_nothing():
    # Hook fires but injects nothing. Exit 0 (never block / never error).
    raise SystemExit(0)

# ----------------------------------------------------------------------------- config
def env(name, default):
    v = os.environ.get(name)
    return v if v is not None and v != "" else default

def env_int(name, default):
    try:
        return int(str(env(name, default)).strip())
    except Exception:
        return int(default)

def truthy_str(v):
    return str(v).strip().lower() in ("1", "true", "yes", "on")

ENABLE              = env("SEARCHOCLOCK_ENABLE", "1")
COOLDOWN_SEC        = env_int("SEARCHOCLOCK_COOLDOWN_SEC", 900)
MIN_INTERVAL_SEC    = env_int("SEARCHOCLOCK_MIN_INTERVAL_SEC", 60)
MAX_PER_SESSION     = env_int("SEARCHOCLOCK_MAX_PER_SESSION", 8)
RESEARCH_WINDOW_SEC = env_int("SEARCHOCLOCK_RESEARCH_WINDOW_SEC", 600)
REPEAT_ESCALATE     = env_int("SEARCHOCLOCK_REPEAT_ESCALATE", 2)
SEVERITY_MIN        = str(env("SEARCHOCLOCK_SEVERITY_MIN", "low")).lower()
TEAM_SIZE           = max(1, min(5, env_int("SEARCHOCLOCK_TEAM_SIZE", 3)))
EXCERPT_CHARS       = max(120, env_int("SEARCHOCLOCK_EXCERPT_CHARS", 1200))
BACKEND             = str(env("SEARCHOCLOCK_BACKEND", "auto")).lower()
SOLUTION_MODE       = str(env("SEARCHOCLOCK_SOLUTION_MODE", "durable")).lower()   # durable|fast|both
MIN_CANDIDATES      = max(1, min(7, env_int("SEARCHOCLOCK_MIN_CANDIDATES", 3)))   # solution-space floor
PROBE_ALL           = truthy_str(env("SEARCHOCLOCK_PROBE_ALL", "1"))             # force probe-all+durability ranking
VALIDATE            = truthy_str(env("SEARCHOCLOCK_VALIDATE", "1"))              # independent second-model gate
VALIDATOR_MODEL     = env("SEARCHOCLOCK_VALIDATOR_MODEL", "claude-haiku-4-5-20251001")
VALIDATOR_ESCALATE  = env("SEARCHOCLOCK_VALIDATOR_ESCALATE_MODEL", "claude-sonnet-4-6")
VALIDATOR_XPROVIDER = env("SEARCHOCLOCK_VALIDATOR_CROSS_PROVIDER", "")
VALIDATE_MIN_CONF   = env_int("SEARCHOCLOCK_VALIDATE_MIN_CONFIDENCE", 4)
FAILURE_PATTERN     = env("SEARCHOCLOCK_FAILURE_PATTERN", "")      # opt-in soft-failure regex
IGNORE_CMD_PATTERN  = env("SEARCHOCLOCK_IGNORE_CMD_PATTERN", "")   # extra ignore regex
STATE_DIR           = env("SEARCHOCLOCK_STATE_DIR", os.path.join(PROJECT_DIR, ".searchoclock"))
GOAL_SCOPE          = env("SEARCHOCLOCK_GOAL_SCOPE", "auto")
MAX_GLOBAL          = env_int("SEARCHOCLOCK_MAX_GLOBAL", 24)                      # cross-agent ceiling (workflow concurrency)
AGENT_KEY_FIELDS    = [s.strip() for s in env("SEARCHOCLOCK_AGENT_KEY_FIELDS", "agent_id,agent_type,subagent_id,subagentType,parent_tool_use_id,agentId").split(",") if s.strip()]
WORKFLOW_TEAM_SIZE  = max(1, min(5, env_int("SEARCHOCLOCK_WORKFLOW_TEAM_SIZE", 2)))
PROACTIVE           = truthy_str(env("SEARCHOCLOCK_PROACTIVE", "0"))             # Tier-1 pre-flight (opt-in)
PROACTIVE_GUARD     = str(env("SEARCHOCLOCK_PROACTIVE_GUARD", "off")).lower()    # off|ask|deny for destructive
PROACTIVE_TRIGGERS  = set(s.strip() for s in env("SEARCHOCLOCK_PROACTIVE_TRIGGERS", "dep,destructive,version").split(",") if s.strip())
SCORECARD           = truthy_str(env("SEARCHOCLOCK_SCORECARD", "0"))

# GUARD 6 — master kill switch (debug modes still render so authors can inspect)
if not truthy_str(ENABLE) and COMMAND not in ("text", "--text", "json", "--json", "test", "selftest"):
    out_nothing()

SEV_RANK = {"low": 0, "medium": 1, "high": 2}

# ----------------------------------------------------------------------------- input
def read_input():
    try:
        raw = open(INPUT_FILE, "r", encoding="utf-8", errors="replace").read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}

data = read_input()

def g(d, *keys):
    for k in keys:
        if isinstance(d, dict) and k in d and d[k] not in (None, ""):
            return d[k]
    return None

event     = g(data, "hook_event_name") or ""
tool_name = g(data, "tool_name") or ""
session_id = str(g(data, "session_id") or "default")

# Per-agent state namespace (concurrency-safe for dynamic-workflow / parallel agents):
# up to 16 sibling agents may share one session_id, so budgets/cooldowns bucket per agent.
agent_id = str(g(data, *AGENT_KEY_FIELDS) or "")
if not agent_id:
    agent_id = (os.environ.get("CLAUDE_CODE_SESSION_ID") or session_id) + ":" + str(os.getppid())
agent_key = (session_id + "::" + agent_id)[:120]

# tool_input.command
tool_input = data.get("tool_input")
cmd = ""
if isinstance(tool_input, dict):
    cmd = str(tool_input.get("command") or tool_input.get("cmd") or "")
elif isinstance(tool_input, str):
    cmd = tool_input

# tool_response (string OR {stdout,stderr,interrupted,isImage,...})
tr = data.get("tool_response")
stdout = stderr = ""
tr_dict = tr if isinstance(tr, dict) else {}
if isinstance(tr, str):
    stdout = tr
elif isinstance(tr, dict):
    stdout = str(tr.get("stdout") or "")
    stderr = str(tr.get("stderr") or "")
    if not stdout and not stderr:
        c = tr.get("content") or tr.get("output") or tr.get("result")
        if isinstance(c, str):
            stdout = c

def to_int(x):
    try:
        return int(x)
    except Exception:
        return None

# exit code: the Bash tool_response shape is undocumented and real payloads do NOT
# carry a top-level exit code, so read only specific tool_response keys and avoid
# generic top-level keys (status/code) that could false-positive on a stray field.
exit_code = None
for k in ("exit_code", "exitCode", "returnCode"):
    ec = to_int(tr_dict.get(k))
    if ec is not None:
        exit_code = ec
        break

is_err = False
for k in ("is_error", "isError", "error"):
    v = tr_dict.get(k)
    if v is True or (isinstance(v, str) and v.strip()):
        is_err = True
        break
# interruption: PostToolUse Bash uses tool_response.interrupted; PostToolUseFailure
# uses a top-level is_interrupt.
interrupted = bool(tr_dict.get("interrupted")) or bool(data.get("is_interrupt"))
top_error = data.get("error")
top_error_str = top_error if isinstance(top_error, str) else (json.dumps(top_error) if top_error else "")

combined = "\n".join(x for x in (stderr, stdout, top_error_str) if x)

# ----------------------------------------------------------------------------- failure decision
def is_failure():
    if event == "PostToolUseFailure":
        return True
    # PostToolUse fires on SUCCESS; only treat as failure on an EXPLICIT signal.
    if exit_code is not None and exit_code != 0:
        return True
    if is_err or interrupted:
        return True
    if top_error_str:
        return True
    # opt-in soft-failure regex (never default-on, to avoid false positives on success)
    if FAILURE_PATTERN:
        try:
            if re.search(FAILURE_PATTERN, combined, re.I):
                return True
        except Exception:
            pass
    return False

# ----------------------------------------------------------------------------- text/json debug modes
def excerpt_text():
    src = stderr or top_error_str or stdout or "(no output captured)"
    src = src.strip() or "(no output captured)"
    if len(src) <= EXCERPT_CHARS:
        return src
    head = src[: EXCERPT_CHARS * 2 // 3]
    tail = src[-EXCERPT_CHARS // 3:]
    return head + "\n  ...[truncated]...\n  " + tail

def head_command(c):
    c = (c or "").strip()
    if not c:
        return ""
    first_line = c.splitlines()[0]
    try:
        import shlex
        parts = shlex.split(first_line)
    except Exception:
        parts = first_line.split()
    i = 0
    while i < len(parts) and ("=" in parts[i]) and not parts[i].startswith("-"):
        i += 1  # skip leading VAR=value env assignments
    while i < len(parts) and parts[i] in ("sudo", "env", "command", "time", "nice", "nohup", "exec", "xargs", "stdbuf"):
        i += 1
    head = parts[i] if i < len(parts) else (parts[0] if parts else "")
    return os.path.basename(head)

BUILTIN_IGNORE = re.compile(
    r"^(searchoclock|websearch|webfetch|grep|rg|ag|find|fd|ls|cat|head|tail|less|more|"
    r"pwd|cd|echo|printf|true|false|:|which|type|whatis|man|tldr|curl|wget|http|https|"
    r"httpie|lynx|w3m|clear)$",
    re.I,
)

def should_ignore_cmd(c):
    head = head_command(c)
    if head and BUILTIN_IGNORE.match(head):
        return True
    # only ignore --help/--version for a SIMPLE command (no chaining), so a failing
    # compound command that merely contains a help/version token still fires.
    if re.search(r"(^|\s)(--help|--version)(\s|$)", c or "") and not re.search(r"[;&|\n]", c or ""):
        return True
    if re.search(r"\bgh\s+(api|search)\b", c or ""):
        return True
    if IGNORE_CMD_PATTERN:
        try:
            if re.search(IGNORE_CMD_PATTERN, c or "", re.I):
                return True
        except Exception:
            pass
    return False

def error_signature(c, exc):
    norm = exc or ""
    norm = re.sub(r"[A-Za-z]:\\\\[^\s:]+", "<path>", norm)          # windows paths
    norm = re.sub(r"(/[\w.\-]+){2,}/?", "<path>", norm)             # unix paths
    norm = re.sub(r"\b0x[0-9a-fA-F]+\b", "<addr>", norm)           # hex addresses
    norm = re.sub(r"\b[0-9a-fA-F]{7,40}\b", "<hash>", norm)        # sha/hashes
    norm = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}\b", "<uuid>", norm)
    norm = re.sub(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}[:\d.]*Z?", "<ts>", norm)
    norm = re.sub(r"\b\d+\b", "N", norm)                            # line/col/pid/ports
    norm = re.sub(r"\s+", " ", norm).strip().lower()
    key = (head_command(c) + " :: " + norm)[:600]
    return hashlib.sha1(key.encode("utf-8", "replace")).hexdigest()[:12]

def severity_of(occurrences, c, exc):
    t = ((c or "") + " " + (exc or "")).lower()
    sec = re.search(r"\b(auth|credential|credentials|permission denied|unauthorized|forbidden|401|403|token|secret|cert|tls|ssl|payment|billing)\b", t)
    destructive = re.search(r"\b(database|migration|drop table|production|prod|deploy|data loss|truncate)\b", t)
    breadth = re.search(r"build failed|compilation|compile error|\bci\b|test suite|\d+ (errors|failing|failed)|cannot find module|modulenotfounderror|no such file", t)
    sev = "low"
    if sec or destructive or breadth:
        sev = "medium"
    if (sec and destructive) or occurrences >= REPEAT_ESCALATE:
        sev = "high"
    return sev

def goal_context():
    # forced literal / off
    gs = GOAL_SCOPE
    if gs and gs.lower() not in ("auto", "off"):
        return gs.strip()[:240]
    if gs and gs.lower() == "off":
        return None
    # opportunistic input fields (unverified across CLI versions; harmless if absent)
    for k in ("goal", "objective", "completion_condition"):
        v = data.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()[:240]
    def first_heading(path, limit=2000):
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                txt = fh.read(limit)
        except Exception:
            return None
        for line in txt.splitlines():
            s = line.strip()
            if not s:
                continue
            m = re.match(r"^(?:#+\s*|goal:\s*|##\s*goal\s*:?\s*)(.+)$", s, re.I)
            if m and m.group(1).strip():
                return m.group(1).strip()[:240]
            if s.lower() not in ("# spec", "spec"):
                return re.sub(r"^#+\s*", "", s)[:240]
        return None
    # claudemax Mode B per-subspec SPEC
    for sp in sorted(glob.glob(os.path.join(PROJECT_DIR, ".claudemax", "state", "agent-teams-*", "*.SPEC.md"))):
        h = first_heading(sp)
        if h:
            return h
    # repo-root SPEC.md
    h = first_heading(os.path.join(PROJECT_DIR, "SPEC.md"))
    if h:
        return h
    return None

# ----------------------------------------------------------------------------- state
def load_state():
    try:
        with open(os.path.join(STATE_DIR, "state.json"), "r", encoding="utf-8") as fh:
            s = json.load(fh)
            return s if isinstance(s, dict) else {}
    except Exception:
        return {}

def save_state(state):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".state.", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, os.path.join(STATE_DIR, "state.json"))
    except Exception:
        pass  # fail-open: state is best-effort

def write_last_error(cmd, exc, sig, sev, scope, now_local, now_utc):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        body = (
            "# searchoclock — last captured failure\n\n"
            f"- Captured: {now_local} (UTC {now_utc})\n"
            f"- Error signature: `{sig}`\n"
            f"- Severity: {sev}\n"
            f"- Scope: {scope or '(none detected — keep the fix minimal and local)'}\n\n"
            "## Failed command\n\n```\n" + (cmd or "(unknown)") + "\n```\n\n"
            "## Error excerpt\n\n```\n" + (exc or "(no output captured)") + "\n```\n"
        )
        with open(os.path.join(STATE_DIR, "last-error.md"), "w", encoding="utf-8") as fh:
            fh.write(body)
    except Exception:
        pass

# ----------------------------------------------------------------------------- clock
def clock():
    local_now = dt.datetime.now().astimezone()
    utc_now = local_now.astimezone(dt.timezone.utc)
    return (
        local_now.isoformat(timespec="seconds"),
        utc_now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        str(utc_now.year),
    )

_CLI_VERSION = None
def cli_version():
    # Lazy + cached: only the fire path (and debug modes) pay for it — never every
    # successful Bash call. Normalized to bare semver; fully fail-soft.
    global _CLI_VERSION
    if _CLI_VERSION is not None:
        return _CLI_VERSION
    v = "unknown"
    try:
        import shutil
        import subprocess
        if shutil.which("claude"):
            r = subprocess.run(["claude", "--version"], capture_output=True, text=True, timeout=2)
            lines = (r.stdout or "").strip().splitlines()
            line = lines[0] if lines else ""
            m = re.search(r"\d+\.\d+\.\d+", line)
            v = m.group(0) if m else (line or "unknown")
    except Exception:
        v = "unknown"
    _CLI_VERSION = v
    return v

# ----------------------------------------------------------------------------- protocol
PROTOCOL = """SEARCH O'CLOCK — date-aware failure troubleshooting (context from the searchoclock plugin)

Factual context: a Bash command just failed. The current date is {{NOW_LOCAL}} (UTC {{NOW_UTC}}); the year is {{YEAR}}. This Claude Code reports version {{CLI_VERSION}}. WebSearch and WebFetch are available. Fixes for fast-moving tools/libraries go stale fast, so a remembered fix may predate a {{YEAR}} breaking change — and the first fix that makes the error vanish is often a brittle band-aid, not the durable root-cause fix.

FAILED COMMAND:
  {{CMD}}

ERROR (excerpt):
{{ERROR_EXCERPT}}

ERROR SIGNATURE: {{ERROR_SIGNATURE}}    SEVERITY: {{SEVERITY}}    MODE: {{MODE}}

SCOPE: {{GOAL_CONTEXT}}

{{MODE_BANNER}}

1. Name the failure in one line — the actual error class and the specific tool/library/version implicated (from the lockfile/manifest), not a guess.

2. Dispatch the researcher (clean context). Use the Agent tool (Task on older CLIs) to spawn subagent type `searchoclock:searchoclock-researcher` with this task:
     {{RESEARCH_TASK}}
{{SEVERITY_NOTE}}

3. Query shapes (not bare): "<tool> <error> {{YEAR}}", "<tool> fix after <version>", "<tool> changelog breaking change {{YEAR}}", "<tool> migration {{YEAR}}". Prefer official docs / changelogs / release notes / the project's issue tracker (maintainer comments, linked PRs) over blogs; do NOT default to the top-voted Stack Overflow answer or newest blog — popularity/recency is not a durability signal.

4. DURABILITY RUBRIC — score each candidate per item (-1 brittle / 0 / +1 durable; weight the first three ~2x):
   - ROOT CAUSE: makes this exact failure non-reproducible by the same trigger, not just silences the symptom.
   - OFFICIAL & FORWARD-COMPATIBLE: maintainers' supported migration/upgrade/config, within ~2 major releases of current; not monkey-patching internals/undocumented behaviour.
   - NOT EOL/DEPRECATED: lands on a supported version with runway, not a pin/downgrade onto an EOL/deprecated one.
   - SECURITY: doesn't weaken posture (no disabled audit/SSL/signature checks; prefer override-to-a-PATCHED-version over pin-to-silence).
   - MAINTENANCE/BLAST RADIUS: removes complexity vs adds a permanent exception; minimal coupling.
   - REVERSIBILITY + TEST: cheap to back out, lockable by a regression test/CI check that fails if the bug returns.
   BRITTLE-HACK flags (count against): --force / --no-verify / --legacy-peer-deps, blanket downgrade or pin, eslint-disable / @ts-ignore / @ts-nocheck / any-cast, hand-edited lockfile or go.sum, FROM :latest, bypassed checksum/verify. OK ONLY as a commented, ticket-tracked, narrow, time-boxed bridge.

5. Cross-check >=2 independent current sources per claim; on conflict prefer the most recent primary source and say so. Verify dependency/build fixes on a CLEAN checkout / frozen lockfile (npm ci, pnpm --frozen-lockfile, uv sync --frozen, cargo --locked), not just locally — passing tests alone is not proof of durability.

6. {{RECOMMEND_LINE}}

{{VALIDATE_BLOCK}}

10. Optional: if `.claudemax/memory.sqlite` exists, look up signature {{ERROR_SIGNATURE}} in errors_solutions first and record the chosen fix afterward; if `plan-detection.json` exists, respect the remaining credit budget before fanning out.

Stay within SCOPE — no unrelated refactors or side-quests; if a durable fix must leave this scope, say so and stop. Fallback: if this guidance is unclear or truncated, run  /searchoclock  (it reads .searchoclock/last-error.md)."""

PREFLIGHT = """SEARCH O'CLOCK — pre-flight currency check (searchoclock plugin, opt-in)

You are ABOUT to run a {{TRIGGER_CLASS}} command. Today is {{NOW_LOCAL}} (UTC {{NOW_UTC}}); the year is {{YEAR}}. This surface moves fast — the most-common pattern in training data is often no longer the current one.

ABOUT TO RUN:
  {{CMD}}

TRIGGER: {{TRIGGER_CLASS}}    SEVERITY: {{SEVERITY}}

Before you write or run this:
1. Verify the CURRENT approach as of {{NOW_LOCAL}} — check the official docs / changelog / release notes for the exact tool+version implicated (from the lockfile/manifest), not your memory. A one-shot WebSearch ("<tool> <op> {{YEAR}}", "<tool> changelog breaking change {{YEAR}}", "<tool> migration {{YEAR}}") is usually enough at this stage.
2. Prefer the maintainers' current supported path; if you pin a version, pin to a supported, non-EOL one and say why.
3. {{TRIGGER_HINT}}

This is a NUDGE, not a block — proceed once you've confirmed the approach is current. If it's version-sensitive or irreversible and you're unsure, dispatch `searchoclock:searchoclock-researcher` for a quick dated check. If the command fails anyway, the searchoclock failure path fires with full troubleshooting."""

SEVERITY_NOTE_HIGH = (
    "   - SEVERITY is high (repeated or high-risk). Spawn {N} `searchoclock:searchoclock-researcher` subagents IN PARALLEL this turn, ONE PER CANDIDATE fix/hypothesis (each researches its own candidate in clean context), THEN run an INDEPENDENT judge/verifier — external to the generators, never self-selection — that compares the full candidate set at once (generative-selection / pairwise, not isolated scoring) and runs an adversarial 'try to break the chosen fix' pass before anything is applied. For a large multi-component failure you MAY escalate to full Agent Teams (export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1; requires Opus 4.6+)."
)
SEVERITY_NOTE_MEDIUM = (
    "   - SEVERITY is medium (security/destructive/build-wide domain). Use one researcher but require an explicit >=2-source cross-check, the reproducibility gate, and an adversarial self-review before recommending."
)

def render(now_local, now_utc, year, cmd, excerpt, sig, sev, scope):
    excerpt_block = "\n".join("  " + ln for ln in (excerpt or "(no output captured)").splitlines()) or "  (no output captured)"
    excerpt_oneline = re.sub(r"\s+", " ", excerpt or "(no output captured)").strip()[:280]
    scope_txt = scope or "No active goal/SPEC detected — keep the fix minimal and local to the failing command; do not refactor unrelated code."
    cmd_txt = cmd or "(unknown)"
    probe = PROBE_ALL and SOLUTION_MODE in ("durable", "both")
    mode_label = SOLUTION_MODE + ("" if PROBE_ALL else "+probe-all-off")

    if probe:
        mode_banner = (
            "This plugin is configured to probe the FULL solution space and recommend the most effective "
            "LONG-TERM (SOTA %s) fix by default — not the fastest patch:" % year
        )
        research_task = (
            '"Enumerate >= %d distinct candidate fixes covering the realistic solution space (e.g. upgrade to the '
            'release that fixed it; a scoped overrides/constraints to a PATCHED transitive version; the official '
            'codemod/migration; a documented config change; a documented workaround). For EACH candidate: run '
            'date/version-qualified live searches (year %s), cross-check >=2 INDEPENDENT current sources, cite each '
            "source's publish/update date AND your access date (%s), and score it on the DURABILITY RUBRIC below. "
            "RETURN the candidate table (per-candidate sources + durability score), the RECOMMENDED durable SOTA "
            "fix, the fastest STOP-GAP labelled separately, and any BRITTLE-HACK flags. Command: %s. Error: %s. "
            'Signature: %s. Stay scoped to: %s"'
            % (MIN_CANDIDATES, year, now_local, cmd_txt, excerpt_oneline, sig, scope_txt)
        )
        if SOLUTION_MODE == "both":
            recommend_line = (
                "Return BOTH the most effective LONG-TERM fix (root cause + exact change + dated sources + "
                "confidence) AND the fastest STOP-GAP labelled separately; flag BRITTLE hacks. If no live source "
                "confirms a durable fix for this version as of %s, say insufficient_data rather than guessing." % year
            )
        else:
            recommend_line = (
                "Recommend the most effective LONG-TERM fix (root cause + exact change + dated sources + "
                "confidence); label the fastest STOP-GAP separately (viable only with the four bridge conditions: "
                "comment, ticket, narrow scope, time-box); flag BRITTLE hacks. If no live source confirms a durable "
                "fix for this version as of %s, say insufficient_data rather than guessing." % year
            )
    else:
        mode_banner = (
            "This run is in single-fix mode (SEARCHOCLOCK_SOLUTION_MODE=fast or SEARCHOCLOCK_PROBE_ALL=0): return "
            "the single most reliable verified fix, still dated and brittle-flagged."
        )
        research_task = (
            '"Find the single most reliable fix (prefer the more durable option when it is no slower). Run '
            "date/version-qualified live searches (year %s), cross-check >=2 INDEPENDENT current sources, cite each "
            "source's publish/update date AND your access date (%s). RETURN root cause + exact change + >=2 dated "
            "sources + confidence, and flag any BRITTLE-HACK content. Command: %s. Error: %s. Signature: %s. Stay "
            'scoped to: %s"'
            % (year, now_local, cmd_txt, excerpt_oneline, sig, scope_txt)
        )
        recommend_line = (
            "Recommend the single verified fix (root cause + exact change + dated sources + confidence); flag "
            "brittle hacks; if no live source confirms a fix for this version as of %s, say insufficient_data." % year
        )

    if sev == "high":
        sev_note = SEVERITY_NOTE_HIGH.replace("{N}", str(max(2, min(TEAM_SIZE, 5))))
    elif sev == "medium":
        sev_note = SEVERITY_NOTE_MEDIUM
    else:
        sev_note = "   - SEVERITY is low. One researcher is enough; still probe the candidates and verify against live sources before applying."

    if VALIDATE:
        xprov = VALIDATOR_XPROVIDER or "set SEARCHOCLOCK_VALIDATOR_CROSS_PROVIDER to a non-Anthropic model"
        validate_block = (
            "7. EXTRACT A CLAIM OBJECT. From the recommended fix build ONLY: the literal error + signature, the failed command, the proposed change as a concrete diff/command(s), a one-line falsifiable claim, the cited sources WITH their verbatim fetched text (not links), and the reproducibility command. Discard the researcher's prose and reasoning.\n\n"
            "8. VALIDATE WITH AN INDEPENDENT SECOND MODEL. Dispatch subagent type `searchoclock:searchoclock-validator` (model %s) with ONLY the claim object + raw evidence + literal error — do NOT reveal who proposed it or pass its reasoning. It returns a binary, evidence-quoted JSON verdict (agree, per-source support, error_actually_addressed, reproducibility_plausible, new_risks, confidence 1-5).\n\n"
            "9. TRUST GATE. Adopt the fix ONLY IF agree==true AND every cited source supports it AND error_actually_addressed AND confidence>=%d AND no unmanaged brittle/security new_risk. Otherwise DO NOT apply it: feed the validator's objections back to the researcher for a revised candidate, or re-validate with %s. Effortless 100%% agreement with no quoted evidence is SUSPECT, not approval — re-run the reproducibility check. NOTE: %s is the same model family as the proposer, so for security/destructive/irreversible fixes use a different-provider verifier (%s) — same-family agreement is correlated, not fully independent."
            % (VALIDATOR_MODEL, VALIDATE_MIN_CONF, VALIDATOR_ESCALATE, VALIDATOR_MODEL, xprov)
        )
    else:
        validate_block = "7. (Independent second-model validation is disabled — SEARCHOCLOCK_VALIDATE=0. The recommended fix is unverified by a second model; apply with extra care.)"

    txt = PROTOCOL
    repl = {
        "{{VALIDATE_BLOCK}}": validate_block,
        "{{NOW_LOCAL}}": now_local,
        "{{NOW_UTC}}": now_utc,
        "{{YEAR}}": year,
        "{{CLI_VERSION}}": cli_version(),
        "{{CMD}}": cmd_txt,
        "{{ERROR_EXCERPT}}": excerpt_block,
        "{{ERROR_SIGNATURE}}": sig,
        "{{SEVERITY}}": sev,
        "{{MODE}}": mode_label,
        "{{GOAL_CONTEXT}}": scope_txt,
        "{{MODE_BANNER}}": mode_banner,
        "{{RESEARCH_TASK}}": research_task,
        "{{RECOMMEND_LINE}}": recommend_line,
        "{{SEVERITY_NOTE}}": sev_note,
    }
    for k, v in repl.items():
        txt = txt.replace(k, v)
    # hard cap below the 10,000-char additionalContext limit
    if len(txt) > 9500:
        txt = txt[:9400] + "\n...[searchoclock context truncated to fit the 10k cap]..."
    return txt

def emit(context, ev):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": ev or "PostToolUseFailure",
            "additionalContext": context,
        },
        "suppressOutput": True,
    }))
    raise SystemExit(0)

# ----------------------------------------------------------------------------- debug modes
if COMMAND in ("text", "--text", "json", "--json", "test", "selftest"):
    now_local, now_utc, year = clock()
    exc = excerpt_text()
    c = cmd or "npm run build"
    if not stderr and not stdout and not top_error_str:
        exc = "Error: Cannot find module 'vite'\nRequire stack: ...(demo error)"
    sig = error_signature(c, exc)
    scope = goal_context()
    sev = severity_of(1, c, exc)
    rendered = render(now_local, now_utc, year, c, exc, sig, sev, scope)
    if COMMAND in ("json", "--json"):
        print(json.dumps({
            "command": c, "signature": sig, "severity": sev,
            "goal_context": scope, "now_local": now_local, "now_utc": now_utc,
            "cli_version": cli_version(), "event": event or "(none)",
            "additionalContext_len": len(rendered),
        }, indent=2))
    else:
        print(rendered)
    raise SystemExit(0)

# ----------------------------------------------------------------------------- preflight mode (Tier-1 proactive PreToolUse; opt-in, non-blocking by default)
if COMMAND == "preflight":
    if not PROACTIVE:
        raise SystemExit(0)                       # disabled => allow, no context
    if tool_name and tool_name != "Bash":
        raise SystemExit(0)
    c = (cmd or "").strip()
    if not c:
        raise SystemExit(0)
    head = head_command(c)
    cl = c.lower()
    trig = None
    key = None
    if "dep" in PROACTIVE_TRIGGERS and re.search(r"\b(npm|pnpm|yarn|bun)\s+(i|install|add|up|upgrade|update)\b|\b(pip|pip3|uv|poetry)\s+(install|add)\b|\bcargo\s+add\b|\bgo\s+get\b|\bgem\s+install\b|\b(apt|apt-get|brew)\s+install\b|\bbundle\s+add\b", cl):
        trig = "dependency"
        m = re.search(r"\b(?:add|install|get)\s+([@\w./-]+)", cl)
        key = "dep:" + (m.group(1) if m else head)
    if trig is None and "destructive" in PROACTIVE_TRIGGERS and re.search(r"\brm\s+-[a-z]*r[a-z]*f|\brm\s+-[a-z]*f[a-z]*r\b|\bfind\b.*\s-delete\b|\bgit\s+push\b.*(--force|-f)\b|\bdrop\s+table\b|\btruncate\s+table\b|\b(prisma|alembic|rails|knex|sequelize)\b.*\bmigrat|\bterraform\s+(apply|destroy)\b|\bkubectl\s+delete\b|\bhelm\s+uninstall\b|\bdocker\s+system\s+prune\b|\b(deploy|release)\b.*\b(prod|production)\b|\b(prod|production)\b.*\b(deploy|release)\b", cl):
        trig = "destructive"
        key = "destructive:" + head
    if trig is None and "version" in PROACTIVE_TRIGGERS and re.search(r"\b(next|react|vite|webpack|esbuild|rollup|eslint|typescript|tsc|tailwind|langchain|openai|anthropic|cuda|torch|pytorch|tensorflow)\b|\bnpm\s+ci\b|--frozen-lockfile|--locked", cl):
        trig = "version-sensitive"
        key = "version:" + head
    if trig is None:
        raise SystemExit(0)                       # no risk trigger => allow, silent (zero noise)
    now = int(time.time())
    state = load_state()
    agents = state.get("agents")
    if not isinstance(agents, dict):
        agents = {}
        state["agents"] = agents
    b = agents.get(agent_key)
    if not isinstance(b, dict):
        b = {"session_count": 0, "last_fire_epoch": 0, "researching_until": 0, "fired": {}, "last_seen": now}
        agents[agent_key] = b
    b["last_seen"] = now
    briefed = b.get("briefed")
    if not isinstance(briefed, dict):
        briefed = {}
        b["briefed"] = briefed
    if key in briefed:
        save_state(state)
        raise SystemExit(0)                       # already briefed this surface this agent
    briefed[key] = now
    save_state(state)
    now_local, now_utc, year = clock()
    sev = "high" if trig == "destructive" else ("medium" if trig == "version-sensitive" else "low")
    hint = {
        "dependency": "Confirm this package's current name, latest supported version, and required peer-deps/config as of %s before adding it — don't pin to a remembered version." % year,
        "destructive": "This is destructive/irreversible. Confirm the current safe procedure AND a rollback/backup path before running; a remembered flag/command may have changed.",
        "version-sensitive": "Check the changelog/migration guide for this version as of %s; verify the API/flags you're about to use still exist and aren't deprecated." % year,
    }[trig]
    brief = PREFLIGHT
    for k, v in {"{{TRIGGER_CLASS}}": trig, "{{NOW_LOCAL}}": now_local, "{{NOW_UTC}}": now_utc,
                 "{{YEAR}}": year, "{{CMD}}": c, "{{SEVERITY}}": sev, "{{TRIGGER_HINT}}": hint}.items():
        brief = brief.replace(k, v)
    if len(brief) > 9500:
        brief = brief[:9400] + "\n...[searchoclock pre-flight truncated]..."
    decision = "allow"
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision, "additionalContext": brief}, "suppressOutput": True}
    if trig == "destructive" and PROACTIVE_GUARD in ("ask", "deny"):
        out["hookSpecificOutput"]["permissionDecision"] = PROACTIVE_GUARD
        out["hookSpecificOutput"]["permissionDecisionReason"] = "searchoclock: destructive/irreversible command — verify the current safe procedure and a rollback path first."
    print(json.dumps(out))
    raise SystemExit(0)

# ----------------------------------------------------------------------------- hook mode
# Only Bash failures are in scope (other tools do not reliably fire failure hooks).
if tool_name and tool_name != "Bash":
    out_nothing()

if not is_failure():
    out_nothing()

if should_ignore_cmd(cmd):
    out_nothing()  # self/research/inspection command — never troubleshoot (loop guard)

excerpt = excerpt_text()
sig = error_signature(cmd, excerpt)
now = int(time.time())

# Per-agent state namespace (agent_key derived above) — concurrency-safe budgets/cooldowns.
state = load_state()
# reset the cross-agent global counter on a new session
if state.get("global_session") != session_id:
    state["global_session"] = session_id
    state["global_count"] = 0
agents = state.get("agents")
if not isinstance(agents, dict):
    agents = {}
    state["agents"] = agents
# GC stale per-agent buckets so state.json doesn't grow across long workflow runs
for _k in list(agents.keys()):
    try:
        if now - int(agents[_k].get("last_seen", 0)) > RESEARCH_WINDOW_SEC * 4:
            del agents[_k]
    except Exception:
        pass
b = agents.get(agent_key)
if not isinstance(b, dict):
    b = {"session_count": 0, "last_fire_epoch": 0, "researching_until": 0, "fired": {}, "last_seen": now}
    agents[agent_key] = b
b["last_seen"] = now
fired = b.get("fired")
if not isinstance(fired, dict):
    fired = {}
    b["fired"] = fired
rec = fired.get(sig) if isinstance(fired.get(sig), dict) else {"last": 0, "count": 0}
rec["count"] = int(rec.get("count", 0)) + 1
occurrences = rec["count"]
fired[sig] = rec

def persist_and_stop():
    save_state(state)
    out_nothing()

# Severity first so a brand-new HIGH-severity failure can bypass the "one research at a
# time" windows; per-signature cooldown, per-agent budget, and the global ceiling always hold.
sev = severity_of(occurrences, cmd, excerpt)
high_bypass = (sev == "high") and not int(rec.get("last", 0))

# GUARD 4 — this agent is already researching the prior failure
if int(b.get("researching_until", 0)) > now and not high_bypass:
    persist_and_stop()
# GUARD 2 — per-agent global rate limit
if (now - int(b.get("last_fire_epoch", 0))) < MIN_INTERVAL_SEC and not high_bypass:
    persist_and_stop()
# GUARD 1 — per-signature cooldown / dedup (always honored, even high severity)
if int(rec.get("last", 0)) and (now - int(rec.get("last", 0))) < COOLDOWN_SEC:
    persist_and_stop()
# GUARD 3 — per-agent session budget (hard ceiling)
if int(b.get("session_count", 0)) >= MAX_PER_SESSION:
    persist_and_stop()
# GUARD 3b — cross-agent global ceiling (so N concurrent agents can't fan out N×)
if int(state.get("global_count", 0)) >= MAX_GLOBAL:
    persist_and_stop()
# severity floor
if SEV_RANK.get(sev, 0) < SEV_RANK.get(SEVERITY_MIN, 0):
    persist_and_stop()

scope = goal_context()
now_local, now_utc, year = clock()

# commit fire (per-agent bucket + global counter)
rec["last"] = now
b["last_fire_epoch"] = now
b["session_count"] = int(b.get("session_count", 0)) + 1
b["researching_until"] = now + RESEARCH_WINDOW_SEC
state["global_count"] = int(state.get("global_count", 0)) + 1
save_state(state)
write_last_error(cmd, excerpt, sig, sev, scope, now_local, now_utc)

emit(render(now_local, now_utc, year, cmd, excerpt, sig, sev, scope), event or "PostToolUseFailure")
PY
