// Warns the user and the model when another live agent works in this checkout, through herdr-workspace-guard.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function workspaceGuard(pi: ExtensionAPI) {
	if (!process.env.HC_TERMINAL_ID) return;
	let pending: string | undefined;

	pi.on("session_start", async (event, ctx) => {
		// Subagents inherit HC_TERMINAL_ID but run headless; only the TUI owns the terminal.
		if (ctx.mode !== "tui" || (event.reason !== "startup" && event.reason !== "resume")) return;
		const r = await pi.exec("herdr-workspace-guard", [ctx.cwd], { timeout: 10_000 }).catch(() => undefined);
		const others = r?.code === 0 ? r.stdout.trim() : "";
		if (!others) return;
		ctx.ui.notify(`Agent ${others} already works in this checkout.`, "warning");
		pending = [
			`Live agent terminal(s) ${others} already work in the checkout holding ${ctx.cwd}.`,
			"They share its jj working copy, so a commit, squash or rebase here rewrites theirs.",
			"Before the first edit, tell the user and move into a workspace of your own.",
		].join(" ");
	});

	pi.on("before_agent_start", async () => {
		if (!pending) return;
		const content = pending;
		pending = undefined;
		return { message: { customType: "workspace-guard", content, display: false } };
	});
}
