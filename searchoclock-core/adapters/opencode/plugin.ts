// opencode adapter for searchoclock-core (TS plugin).
// Uses the `tool.execute.after` lifecycle hook to detect a failed shell tool call,
// pipes a normalized event to `socx hook`, and injects the protocol into output.text
// so the agent reads it. CAVEAT (verified): MCP-tool calls may NOT trigger plugin hooks
// (opencode issue #2319), so MCP-tool failures are not covered here — use socx-run for those.
// Confirm the plugin API shape against https://opencode.ai/docs/plugins (2026).
import { spawnSync } from "node:child_process";

export const SearchOClock = async ({ project, client }: any) => ({
  "tool.execute.after": async (input: any, output: any) => {
    try {
      const tool = String(input?.tool ?? "");
      if (!/^(bash|shell|run|command)$/i.test(tool)) return;
      const out = output ?? {};
      const exit = out.exitCode ?? out.exit_code ?? null;
      const stderr = String(out.stderr ?? out.error ?? "");
      const failed = (exit !== null && exit !== 0) || out.isError === true || /\b(error|fatal|exception|traceback|failed)\b/i.test(stderr);
      if (!failed) return;
      const event = JSON.stringify({
        hook_event_name: "command.failed",
        tool_name: "shell",
        command: String(input?.args?.command ?? input?.command ?? ""),
        exit_code: exit, stderr,
      });
      const r = spawnSync("socx", ["hook"], { input: event, encoding: "utf8", env: { ...process.env, SOCX_HARNESS: "opencode" } });
      const protocol = (r.stdout ?? "").trim();
      if (protocol) output.text = (output.text ? output.text + "\n\n" : "") + protocol;
    } catch { /* fail-open: never break the agent loop */ }
  },
});
