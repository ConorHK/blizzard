// Labels the herdr-core terminal with pi's session file, so Ovis can show the chat.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function hcSession(pi: ExtensionAPI) {
	const terminal = process.env.HC_TERMINAL_ID;
	if (!terminal) return;
	let labeled: string | undefined;

	pi.on("session_start", async (_event, ctx) => {
		// Subagents inherit HC_TERMINAL_ID but run headless; only the TUI owns the terminal.
		if (ctx.mode !== "tui") return;
		const file = ctx.sessionManager.getSessionFile();
		if (!file || file === labeled) return;
		const r = await pi.exec("hc", ["label", terminal, `pi.session=${file}`], { timeout: 5_000 });
		if (r.code === 0) labeled = file;
	});
}
