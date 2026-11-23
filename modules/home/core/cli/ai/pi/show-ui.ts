// A show_ui tool: pi shows documents, images, tables and status cards in Herdr's canvas sidebar (ctrl-shift-g).
import { mkdir, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { getImageDimensions } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const terminal = process.env.HC_TERMINAL_ID;
const dir = path.join(process.env.XDG_STATE_HOME ?? path.join(homedir(), ".local", "state"), "pi-ui");
const file = terminal ? path.join(dir, `${terminal}.json`) : undefined;

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

const MAX_DOC = 256 * 1024;
// The canvas fetches an image as base64 through an 8 MiB pipe.
const MAX_IMAGE = 5 * 1024 * 1024;
const IMAGES: Record<string, string> = {
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".gif": "image/gif",
	".webp": "image/webp",
	".svg": "image/svg+xml",
};
const MARKDOWN = new Set([".md", ".markdown", ".txt", ""]);

type Block = {
	type: string;
	text?: string;
	path?: string;
	language?: string;
	file?: string;
	width?: number;
	height?: number;
	items?: { link?: string }[];
};

/** Why the canvas would refuse these blocks: a link that is not https. */
function problems(blocks: Block[]): string[] {
	const out: string[] = [];
	blocks.forEach((block, b) => {
		(block.items ?? []).forEach((item, i) => {
			if (item.link === undefined) return;
			let ok = false;
			try {
				ok = new URL(item.link).protocol === "https:";
			} catch {}
			if (!ok) out.push(`block ${b} item ${i}: links must be https URLs, not ${JSON.stringify(item.link)}`);
		});
	});
	return out;
}

/** Turns doc and image blocks into what the canvas can draw without reading this machine's files itself. */
async function resolve(blocks: Block[], cwd: string, stamp: string): Promise<Block[]> {
	const out: Block[] = [];
	for (const [i, block] of blocks.entries()) {
		if (block.type !== "doc" && block.type !== "image") {
			out.push(block);
			continue;
		}
		if (!block.path) throw new Error(`block ${i}: ${block.type} needs a path`);
		const source = path.resolve(cwd, block.path);
		const ext = path.extname(source).toLowerCase();
		const size = (await stat(source)).size;
		if (block.type === "doc") {
			if (size > MAX_DOC) throw new Error(`block ${i}: ${block.path} is over ${MAX_DOC / 1024} KB`);
			const text = await readFile(source, "utf8");
			out.push(MARKDOWN.has(ext) ? { type: "markdown", text } : { type: "code", text, language: ext.slice(1) });
			continue;
		}
		if (!(ext in IMAGES)) throw new Error(`block ${i}: ${block.path} is not a PNG, JPEG, GIF, WebP or SVG`);
		if (size > MAX_IMAGE) throw new Error(`block ${i}: ${block.path} is over ${MAX_IMAGE / 1024 / 1024} MB`);
		// A copy beside the state file, so the canvas only ever reads this folder.
		const name = `${terminal}.${stamp}.${i}${ext}`;
		const data = await readFile(source);
		await writeFile(path.join(dir, name), data);
		// The canvas needs the pixel size to keep the image's shape.
		const pixels = getImageDimensions(data.toString("base64"), IMAGES[ext]);
		out.push({ type: "image", file: name, text: block.text, width: pixels?.widthPx, height: pixels?.heightPx });
	}
	return out;
}

/** Removes this terminal's image copies, except the ones the new page uses. */
async function prune(keep: Set<string>): Promise<void> {
	for (const name of await readdir(dir).catch(() => [])) {
		if (name.startsWith(`${terminal}.`) && !name.endsWith(".json") && !name.endsWith(".tmp") && !keep.has(name)) {
			await rm(path.join(dir, name), { force: true });
		}
	}
}

async function show(ctx: ExtensionContext, title: string, blocks: Block[]): Promise<string | undefined> {
	if (!file) return;
	await mkdir(dir, { recursive: true });
	if (!blocks.length) {
		await rm(file, { force: true });
		await prune(new Set());
		return;
	}
	const updated = new Date().toISOString();
	const resolved = await resolve(blocks, ctx.cwd, updated.replace(/[^0-9]/g, ""));
	await prune(new Set(resolved.flatMap((block) => (block.file ? [block.file] : []))));
	const body = { session: ctx.sessionManager.getSessionId(), updated, title, blocks: resolved };
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
			const wrong = problems(params.blocks as Block[]);
			if (wrong.length) throw new Error(`Not shown: ${wrong.join("; ")}`);
			const updated = await show(ctx, params.title, params.blocks as Block[]);
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
		await prune(new Set());
		await pi.exec("hc", ["label", terminal!, "pi.ui="], { timeout: 5_000 }).catch(() => undefined);
	});
}
