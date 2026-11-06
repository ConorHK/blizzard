// A show_ui tool: pi draws cards, tables and buttons in Herdr's canvas sidebar (ctrl-shift-g).
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const terminal = process.env.HC_TERMINAL_ID;
const dir = path.join(process.env.XDG_STATE_HOME ?? path.join(homedir(), ".local", "state"), "pi-ui");
const file = terminal ? path.join(dir, `${terminal}.json`) : undefined;

const Tone = Type.Optional(
	Type.Union([Type.Literal("good"), Type.Literal("bad"), Type.Literal("warn"), Type.Literal("info"), Type.Literal("muted")]),
);
const Item = Type.Object({
	label: Type.Optional(Type.String({ description: "stats: the caption; buttons: the button text" })),
	value: Type.Optional(Type.String({ description: "stats: the big number or word" })),
	text: Type.Optional(Type.String({ description: "list: the line" })),
	detail: Type.Optional(Type.String({ description: "list: a dim second part" })),
	link: Type.Optional(Type.String({ description: "list or buttons: a URL to open on click" })),
	send: Type.Optional(Type.String({ description: "buttons: text typed into this session as the user's next message" })),
	tone: Tone,
});
const Block = Type.Object({
	type: Type.Union(
		["heading", "markdown", "stats", "table", "list", "progress", "code", "buttons"].map((t) => Type.Literal(t)),
		{ description: "what to draw" },
	),
	text: Type.Optional(Type.String({ description: "heading, markdown or code: the text" })),
	language: Type.Optional(Type.String({ description: "code: the language, for highlighting" })),
	label: Type.Optional(Type.String({ description: "progress: the caption" })),
	value: Type.Optional(Type.Number({ description: "progress: done, from 0 to 1" })),
	columns: Type.Optional(Type.Array(Type.String(), { description: "table: the header" })),
	rows: Type.Optional(Type.Array(Type.Array(Type.String()), { description: "table: the cells, row by row" })),
	items: Type.Optional(Type.Array(Item, { description: "stats, list or buttons: the entries" })),
	tone: Tone,
});
const Params = Type.Object({
	title: Type.String({ description: "a short title for the canvas" }),
	blocks: Type.Array(Block, { description: "what to show, top to bottom; an empty list clears the canvas" }),
});

const MAX_SEND = 2000;

/** Why the canvas would refuse these blocks: a link that is not https, or a send that is too long. */
function problems(blocks: { items?: { link?: string; send?: string }[] }[]): string[] {
	const out: string[] = [];
	blocks.forEach((block, b) => {
		(block.items ?? []).forEach((item, i) => {
			if (item.link !== undefined) {
				let ok = false;
				try {
					ok = new URL(item.link).protocol === "https:";
				} catch {}
				if (!ok) out.push(`block ${b} item ${i}: links must be https URLs, not ${JSON.stringify(item.link)}`);
			}
			if (item.send !== undefined && item.send.length > MAX_SEND) {
				out.push(`block ${b} item ${i}: send is over ${MAX_SEND} characters`);
			}
		});
	});
	return out;
}

async function show(ctx: ExtensionContext, title: string, blocks: unknown[]): Promise<string | undefined> {
	if (!file) return;
	await mkdir(dir, { recursive: true });
	if (!blocks.length) {
		await rm(file, { force: true });
		return;
	}
	const updated = new Date().toISOString();
	const body = { session: ctx.sessionManager.getSessionId(), updated, title, blocks };
	// A rename keeps readers from seeing half a file.
	await writeFile(`${file}.tmp`, JSON.stringify(body));
	await rename(`${file}.tmp`, file);
	return updated;
}

export default function (pi: ExtensionAPI) {
	if (!file) return;
	pi.registerTool({
		name: "show_ui",
		label: "Show UI",
		description: [
			"Draw a small UI for the user in Herdr's canvas sidebar, beside this session; each call replaces the last one.",
			"Use it when a status board, table, checklist or choice reads better than prose: deployment state, review findings, a plan with progress.",
			"Blocks: heading {text}, markdown {text}, stats {items: [{label, value, tone}]}, table {columns, rows},",
			"list {items: [{text, detail, link, tone}]}, progress {label, value 0..1}, code {text, language},",
			"buttons {items: [{label, send | link, tone}]}. Tones: good, bad, warn, info, muted.",
			"A button with send types its text into this session as the user's message, so offer choices the user can click;",
			"the canvas shows each button's send text and link host under its label. Links must be https.",
		].join(" "),
		parameters: Params,
		async execute(_id, params, _signal, _onUpdate, ctx) {
			// Subagents inherit HC_TERMINAL_ID but run headless; only the TUI owns the terminal.
			if (ctx.mode !== "tui") {
				return { content: [{ type: "text", text: "No Herdr canvas for this session; nothing shown." }], details: {} };
			}
			const wrong = problems(params.blocks);
			if (wrong.length) throw new Error(`Not shown: ${wrong.join("; ")}`);
			const updated = await show(ctx, params.title, params.blocks);
			// The app sees terminal labels live, so a new value opens the canvas when this session is focused.
			await pi.exec("hc", ["label", terminal!, `pi.ui=${updated ?? ""}`], { timeout: 5_000 }).catch(() => undefined);
			const text = params.blocks.length
				? `Shown in Herdr's canvas (${params.blocks.length} blocks); it opens by itself while the user has this session focused, else with ctrl-shift-g.`
				: "Canvas cleared.";
			return { content: [{ type: "text", text }], details: {} };
		},
	});
	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		await rm(file, { force: true });
		await pi.exec("hc", ["label", terminal!, "pi.ui="], { timeout: 5_000 }).catch(() => undefined);
	});
}
