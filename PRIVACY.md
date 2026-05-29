# Privacy Policy — Search o'Clock

_Last updated: 2026-05-29_

Search o'Clock (`searchoclock`) is a local Claude Code hook — a `bash` + `python3` script that runs
on your own machine. It is designed to collect nothing.

## What it collects: nothing
- **No telemetry, no analytics, no tracking.** The plugin sends no usage data anywhere.
- **No outbound network requests of its own.** `searchoclock.sh` makes no network calls. (It may run
  `claude --version` locally to label the protocol with your CLI version — a local command that
  transmits nothing.)
- **No personal data.** It does not read, store, or transmit credentials, source code, or personal
  information.

## What it stores: local only, on your machine
- A small state file and a `last-error.md` under `.searchoclock/` (or `$SEARCHOCLOCK_STATE_DIR`) in your
  project. These hold the failed command and an error excerpt you already saw in your terminal, used for
  de-duplication/cooldown and the `/searchoclock` fallback. They never leave your machine and you can
  delete them at any time.

## Web research is performed by Claude Code, not by this plugin
When you act on searchoclock's guidance, **Claude Code's own `WebSearch` / `WebFetch` tools** (or a
subagent you dispatch) may query the web — under **your** existing Claude Code permissions and governed
by **Anthropic's** privacy policy and terms, not by this plugin. searchoclock only injects text
suggesting that research; it does not perform, proxy, or intercept it.

## Third parties
The plugin integrates with no third-party services. Any model calls (research, validation) are made by
your own Claude Code session through Anthropic, under your account.

## Changes
Any updates to this policy are recorded in this repository's commit history.

## Contact
Questions: proeliteinterface@gmail.com · <https://github.com/waitdeadai/searchoclock>
