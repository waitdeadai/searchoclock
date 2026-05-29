# Cline adapter (native hook, in-code via @cline/sdk)

Cline's plugin system registers lifecycle hooks **programmatically** (not a declarative `hooks.json`).
In a `@cline/sdk` plugin, register a post-tool / command-completed hook that, on a failed shell tool,
spawns `socx hook` with the normalized event and injects the returned protocol.

```ts
// sketch — confirm the current @cline/sdk hook API before shipping
import { spawnSync } from "node:child_process";
export function register(cline: any) {
  cline.plugins.onToolResult((evt: any) => {
    if (!/^(bash|shell|command)$/i.test(evt.tool ?? "")) return;
    const exit = evt.exitCode ?? null;
    if (!((exit !== null && exit !== 0) || evt.isError)) return;
    const event = JSON.stringify({ hook_event_name: "command.failed", tool_name: "shell",
      command: evt.command ?? "", exit_code: exit, stderr: evt.stderr ?? "" });
    const r = spawnSync("socx", ["hook"], { input: event, encoding: "utf8",
      env: { ...process.env, SOCX_HARNESS: "cline" } });
    if (r.stdout?.trim()) cline.context.add(r.stdout.trim());
  });
}
```
Cline's IDE-extension → SDK migration was in progress as of 2026-05; verify the API. `socx-run` works today regardless.
