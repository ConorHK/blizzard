// Opens /fork and /clone in a new herdr-app pane, so both branches stay live.
import { existsSync } from "node:fs";
import { type ExtensionAPI, SessionManager } from "@earendil-works/pi-coding-agent";

const DRAFT = "fork-draft";

type Content = string | { type: string; text?: string }[];

function textOf(content: Content): string {
	if (typeof content === "string") return content;
	return content.flatMap((part) => (part.type === "text" && part.text ? [part.text] : [])).join("\n");
}

export default function hcFork(pi: ExtensionAPI) {
	pi.registerFlag(DRAFT, { type: "string", description: "Editor text for a forked pane" });

	pi.on("session_start", (event, ctx) => {
		const draft = pi.getFlag(DRAFT);
		if (event.reason === "startup" && ctx.mode === "tui" && typeof draft === "string") ctx.ui.setEditorText(draft);
	});

	pi.on("session_before_fork", async (event, ctx) => {
		const terminal = process.env.HC_TERMINAL_ID;
		const source = ctx.sessionManager.getSessionFile();
		const entry = ctx.sessionManager.getEntry(event.entryId);
		// Subagents inherit HC_TERMINAL_ID but run headless; only the TUI owns the pane.
		if (!terminal || ctx.mode !== "tui" || !source || !existsSync(source) || !entry) return;

		const got = await pi.exec("hc", ["get", terminal, "--json"], { timeout: 5_000 });
		const labels = got.code === 0 ? (JSON.parse(got.stdout).labels as Record<string, string> | null) : null;
		const space = labels?.["herdr.space"];
		const tab = labels?.["herdr.tab"];
		if (!space || !tab) {
			ctx.ui.notify("No herdr-app pane; forking here", "warning");
			return;
		}

		const leaf = event.position === "at" ? entry.id : entry.parentId;
		const message = entry.type === "message" ? entry.message : undefined;
		const draft = event.position === "before" && message?.role === "user" ? textOf(message.content) : "";
		const file = leaf ? SessionManager.open(source, ctx.sessionManager.getSessionDir()).createBranchedSession(leaf) : undefined;
		const model = ctx.model ? ["--model", `${ctx.model.provider}/${ctx.model.id}`] : [];
		const piArgs = [
			...(file && existsSync(file) ? ["--session", file] : []),
			...model,
			"--thinking",
			pi.getThinkingLevel(),
			...(draft ? [`--${DRAFT}=${draft}`] : []),
		];
		// A fork is a sibling, so it must outlive this pane.
		const args = ["run", "--bg", "--json", "--no-parent", "--cwd", ctx.cwd];
		args.push("--label", `herdr.space=${space}`, "--label", `herdr.tab=${tab}`, "--", "pi", ...piArgs);
		const r = await pi.exec("hc", args, { cwd: ctx.cwd, timeout: 30_000 });
		if (r.code !== 0) {
			ctx.ui.notify(`hc run failed: ${(r.stderr || r.stdout).trim()}`, "error");
		} else {
			ctx.ui.notify(`Forked into pane ${(JSON.parse(r.stdout) as { address: string }).address}`, "info");
		}
		return { cancel: true };
	});
}
