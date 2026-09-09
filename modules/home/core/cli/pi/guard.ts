// Adapter: auto-mode-guard.sh decides; pi enforces.
// Guard silence or failure defers (allows).
import { spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const GUARD = "@guard@";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return;
    const command = (event.input as { command?: string })?.command ?? "";
    if (!command) return;
    const payload = JSON.stringify({
      permission_mode: "auto",
      tool_name: "bash",
      tool_input: { command },
      cwd: process.cwd(),
    });
    const r = spawnSync(GUARD, [], { input: payload, encoding: "utf8" });
    const out = (r.stdout ?? "").trim();
    if (!out) return;
    try {
      const decision = JSON.parse(out).hookSpecificOutput;
      if (decision?.permissionDecision === "deny")
        return { block: true, reason: decision.permissionDecisionReason };
    } catch {
      return;
    }
  });
}
