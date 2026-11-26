// Names the Herdr tab after the session's first prompt, through herdr-tab-name.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function tabName(pi: ExtensionAPI) {
	if (!process.env.HC_TERMINAL_ID) return;

	pi.on("input", async (event, ctx) => {
		// herdr-tab-name returns at once and remembers the session, so later prompts cost one hc call.
		if (event.source === "interactive" && ctx.mode === "tui") {
			const session = ctx.sessionManager.getSessionId();
			await pi.exec("herdr-tab-name", [session, event.text], { timeout: 10_000 }).catch(() => undefined);
		}
		return { action: "continue" };
	});
}
