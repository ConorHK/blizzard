// A show_ui tool: pi shows documents, images, tables and status cards in Herdr's canvas sidebar (ctrl-shift-g), through herdr-show.
import { spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const Tone = Type.Optional(
	Type.Union([Type.Literal("good"), Type.Literal("bad"), Type.Literal("warn"), Type.Literal("info"), Type.Literal("muted")]),
);
const Item = Type.Object({
	label: Type.Optional(Type.String({ description: "stats: the caption" })),
	value: Type.Optional(Type.String({ description: "stats: the big number or word" })),
	text: Type.Optional(Type.String({ description: "list: the line" })),
	detail: Type.Optional(Type.String({ description: "list: a dim second part" })),
	link: Type.Optional(Type.String({ description: "list: a URL to open on click" })),
	tone: Tone,
});
const Block = Type.Object({
	type: Type.Union(
		["heading", "markdown", "doc", "image", "stats", "table", "list", "progress", "code"].map((t) => Type.Literal(t)),
		{ description: "what to draw" },
	),
	text: Type.Optional(Type.String({ description: "heading, markdown or code: the text; image: a caption" })),
	path: Type.Optional(Type.String({ description: "doc or image: a file on this machine" })),
	language: Type.Optional(Type.String({ description: "code: the language, for highlighting" })),
	label: Type.Optional(Type.String({ description: "progress: the caption" })),
	value: Type.Optional(Type.Number({ description: "progress: done, from 0 to 1" })),
	columns: Type.Optional(Type.Array(Type.String(), { description: "table: the header" })),
	rows: Type.Optional(Type.Array(Type.Array(Type.String()), { description: "table: the cells, row by row" })),
	items: Type.Optional(Type.Array(Item, { description: "stats or list: the entries" })),
	tone: Tone,
});
const Params = Type.Object({
	title: Type.String({ description: "a short title for the canvas" }),
	blocks: Type.Array(Block, { description: "what to show, top to bottom; an empty list clears the canvas" }),
});

/** Pipes the page to herdr-show, which resolves paths against cwd; rejects with its error. */
function show(page: unknown, cwd: string): Promise<string> {
	return new Promise((resolve, reject) => {
		const child = spawn("herdr-show", [], { cwd, stdio: ["pipe", "pipe", "pipe"] });
		let out = "";
		let err = "";
		child.stdout.on("data", (d) => (out += d));
		child.stderr.on("data", (d) => (err += d));
		child.on("error", reject);
		child.on("close", (code) => (code === 0 ? resolve(out.trim()) : reject(new Error(err.trim() || `herdr-show exited ${code}`))));
		child.stdin.end(JSON.stringify(page));
	});
}

export default function (pi: ExtensionAPI) {
	if (!process.env.HC_TERMINAL_ID) return;
	pi.registerTool({
		name: "show_ui",
		label: "Show UI",
		description: [
			"Show a page to the user in Herdr's canvas sidebar, beside this session; each call replaces the last one.",
			"Use it for something to read or look at: a document, a diagram or screenshot, a table, a status board.",
			"Blocks: heading {text}, markdown {text}, doc {path} (a markdown or text file, or a source file shown as code),",
			"image {path, text} (a PNG, JPEG, GIF, WebP or SVG file with an optional caption), code {text, language},",
			"stats {items: [{label, value, tone}]}, table {columns, rows}, list {items: [{text, detail, link, tone}]},",
			"progress {label, value 0..1}. Tones: good, bad, warn, info, muted.",
			"Paths are files on this machine, read when the tool is called; call it again to show a newer version.",
			"The canvas only displays: the user answers in the session. Links must be https.",
		].join(" "),
		parameters: Params,
		async execute(_id, params, _signal, _onUpdate, ctx) {
			// Subagents inherit HC_TERMINAL_ID but run headless; only the TUI owns the terminal.
			if (ctx.mode !== "tui") {
				return { content: [{ type: "text", text: "No Herdr canvas for this session; nothing shown." }], details: {} };
			}
			const said = await show(params, ctx.cwd);
			const text = params.blocks.length
				? `${said} It opens by itself while the user has this session focused, else with ctrl-shift-g.`
				: said;
			return { content: [{ type: "text", text }], details: {} };
		},
	});
	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		await pi.exec("herdr-show", ["--clear"], { timeout: 5_000 }).catch(() => undefined);
	});
}
