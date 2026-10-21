// Tracks tasks, knowledge and wins in ogham.
import { existsSync, readFileSync } from "node:fs";
import { mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import * as path from "node:path";
import { type Message, Type, uuidv7 } from "@earendil-works/pi-ai";
import {
	convertToLlm,
	defineTool,
	type ExtensionAPI,
	type ExtensionContext,
	getAgentDir,
	serializeConversation,
} from "@earendil-works/pi-coding-agent";
import {
	applyCuration,
	appendTopic,
	CURATE_SYSTEM,
	candidateUrls,
	clip,
	curateInput,
	firstOpen,
	PROMOTE_SYSTEM,
	parseCuration,
	parsePromotion,
	promoteInput,
	relativeLink,
	renderIndex,
	renderWin,
	type TaskRow,
	type Win,
	linkText,
	winsFor,
	withoutBookkeeping,
} from "./curate.ts";
import { type Hit, reindex, search } from "./knowledge.ts";
import { withLock } from "./lock.ts";
import { appendLines, getSection, parseNote, renderNote } from "./note.ts";
import {
	findUrl,
	formatRef,
	linkSlug,
	type NewTask,
	parseRef,
	projectFor,
	projectName,
	readFrontmatter,
	renderTask,
	renderWorker,
	type Role,
	setFrontmatter,
	slugify,
	stamp,
	type TaskRef,
	taskDir,
	taskNotePath,
	titlePrompt,
	workerId,
	workerLine,
	workerNotePath,
	workerSummary,
} from "./vault.ts";

const ENTRY = "ogham-task";
const WINS = "wins.md";
const INDEX = "index.md";
const MAX_TRANSCRIPT = 60_000;
const MAX_CONTEXT = 8_000;

interface Binding {
	ref: TaskRef;
	title: string;
	role: Role;
}

interface BindRequest extends Binding {
	goal?: string;
	link?: string;
	parent?: string;
}

interface Settings {
	model?: string;
	curate?: boolean;
	zg?: string;
	winGuidance?: string;
}

const DESCRIPTION = `Bind this session to an ogham task, a markdown note in the user's notes repo.

Call it when the user says which task they are working on. Pass title to create or reuse a task in the current repo's project. If the user gives a ticket or URL, look up its ID and title first, pass "<ID>: <title>" as title and the URL as link. Pass task ("project/slug") to join a task another session created. Pass done to close the bound task; its knowledge moves to topic notes and its win to wins.md. Pass nothing to list the task's workers with their status, pane, and intercom id.

A side model keeps the task note current after each run.`;

function readSettings(): Settings {
	const file = path.join(getAgentDir(), "ogham.json");
	try {
		return JSON.parse(readFileSync(file, "utf8")) as Settings;
	} catch {
		return {};
	}
}

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_CHILD) return;

	const vault = process.env.OGHAM_VAULT ?? path.join(homedir(), "ogham");
	let settings: Settings = {};
	let bound: Binding | undefined;
	let session = "";
	let related: Hit[] = [];
	let pending: Promise<void> = Promise.resolve();
	let warnedModel = false;
	let indexing: Promise<void> | undefined;
	let indexDirty = false;

	const abs = (relative: string) => path.join(vault, relative);
	const workerFile = () => (bound ? abs(workerNotePath(bound.ref, session)) : undefined);

	async function read(file: string): Promise<string | undefined> {
		return readFile(file, "utf8").catch(() => undefined);
	}

	/** Temp file plus rename; sync never sees halves. */
	async function save(file: string, text: string): Promise<void> {
		const temp = `${file}.${process.pid}.tmp`;
		await writeFile(temp, text);
		await rename(temp, file);
	}

	/** Rereads under the lock, so slow callers never clobber. */
	async function edit(file: string, change: (text: string) => string): Promise<void> {
		await withLock(file, async () => save(file, change(await readFile(file, "utf8"))));
	}

	async function createOnce(file: string, text: string): Promise<boolean> {
		await mkdir(path.dirname(file), { recursive: true });
		try {
			await writeFile(file, text, { flag: "wx" });
			return true;
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
			return false;
		}
	}

	async function updateWorker(status: string): Promise<void> {
		const file = workerFile();
		if (!file || !existsSync(file)) return;
		const updates: Record<string, string> = { status, updated: stamp(new Date()) };
		// pi-intercom sets it in its own session_start.
		const intercom = process.env.PI_INTERCOM_SESSION_ID;
		if (intercom) updates.intercom = intercom;
		await edit(file, (text) => setFrontmatter(text, updates));
	}

	/** Coalesces bursts of writes into one run. */
	function refreshIndex(): void {
		if (indexing) {
			indexDirty = true;
			return;
		}
		indexing = reindex(settings.zg ?? "zg", vault)
			.catch(() => undefined)
			.finally(() => {
				indexing = undefined;
				if (indexDirty) {
					indexDirty = false;
					refreshIndex();
				}
			});
	}

	async function writeIndex(): Promise<void> {
		const projects = abs("projects");
		const rows: TaskRow[] = [];
		for (const project of existsSync(projects) ? await readdir(projects) : []) {
			for (const slug of await readdir(path.join(projects, project)).catch(() => [] as string[])) {
				const file = path.posix.join("projects", project, slug, `${slug}.md`);
				const text = await read(abs(file));
				if (!text) continue;
				const fields = readFrontmatter(text);
				rows.push({
					project,
					file,
					title: /^# (.+)$/m.exec(text)?.[1] ?? slug,
					status: fields.status ?? "active",
					updated: fields.updated ?? fields.created ?? "",
					next: firstOpen(text),
				});
			}
		}
		await withLock(abs(INDEX), () => save(abs(INDEX), renderIndex(rows, existsSync(abs(WINS)))));
	}

	function showStatus(ctx: ExtensionContext, extra?: string): void {
		const text = bound ? `task: ${formatRef(bound.ref)}${extra ? ` (${extra})` : ""}` : undefined;
		ctx.ui.setStatus("ogham", text);
	}

	function resolveModel(ctx: ExtensionContext) {
		const spec = settings.model;
		const slash = spec?.indexOf("/") ?? -1;
		const model = spec && slash > 0 ? ctx.modelRegistry.find(spec.slice(0, slash), spec.slice(slash + 1)) : undefined;
		if (!model && !warnedModel) {
			warnedModel = true;
			ctx.ui.notify(`ogham: ${spec ? `model ${spec} not found` : "no model set"}; using the session model.`, "warning");
		}
		return model ?? ctx.model;
	}

	async function ask(ctx: ExtensionContext, system: string, input: string): Promise<string> {
		const model = resolveModel(ctx);
		if (!model) throw new Error("no model for ogham");
		const message: Message = { role: "user", content: [{ type: "text", text: input }], timestamp: Date.now() };
		const guidance = settings.winGuidance ? `\n\nWin guidance from the user:\n${settings.winGuidance}` : "";
		const response = await ctx.modelRegistry.complete(
			model,
			{ systemPrompt: system + guidance, messages: [message] },
			{ cacheRetention: "none", sessionId: uuidv7(), signal: AbortSignal.timeout(180_000) },
		);
		if (response.stopReason === "error" || response.stopReason === "aborted") {
			throw new Error(response.errorMessage ?? `model ${response.stopReason}`);
		}
		return response.content
			.filter((block): block is { type: "text"; text: string } => block.type === "text")
			.map((block) => block.text)
			.join("\n");
	}

	async function recordWin(win: Win, binding: Binding): Promise<void> {
		const file = taskNotePath(binding.ref);
		const entry = renderWin(win, new Date(), { title: binding.title, file });
		await withLock(abs(WINS), async () => {
			const existing = (await read(abs(WINS))) ?? "# Wins\n\n";
			await save(abs(WINS), `${existing.replace(/\n*$/, "")}\n\n${entry}`);
		});
	}

	async function curate(ctx: ExtensionContext, binding: Binding, transcript: string): Promise<void> {
		const file = abs(taskNotePath(binding.ref));
		const note = await read(file);
		if (!note) return;
		const wins = winsFor((await read(abs(WINS))) ?? "", taskNotePath(binding.ref));
		const candidates = candidateUrls(transcript, note);
		const reply = await ask(ctx, CURATE_SYSTEM, curateInput(note, clip(transcript, MAX_TRANSCRIPT), candidates, wins));
		const update = parseCuration(reply);
		if (!update) throw new Error("curator reply was not JSON");
		const now = new Date();
		await edit(file, (text) => {
			const fields: Record<string, string> = { updated: stamp(now) };
			if (update.state && readFrontmatter(text).status !== "done") fields.status = update.state;
			return setFrontmatter(applyCuration(text, update, now, workerId(session)), fields);
		});
		if (update.win) await recordWin(update.win, binding);
		await writeIndex();
		refreshIndex();
	}

	async function topicList(): Promise<string> {
		const dir = abs("topics");
		const lines: string[] = [];
		for (const name of existsSync(dir) ? (await readdir(dir)).filter((n) => n.endsWith(".md")).sort() : []) {
			const text = (await read(path.join(dir, name))) ?? "";
			const summary = parseNote(text).head.split("\n").find((line) => line && !/^(#|---|[\w-]+: )/.test(line));
			lines.push(`${name.slice(0, -3)}: ${/^# (.+)$/m.exec(text)?.[1] ?? name}${summary ? ` (${summary})` : ""}`);
		}
		return lines.join("\n");
	}

	async function promote(ctx: ExtensionContext, binding: Binding): Promise<string[]> {
		const file = taskNotePath(binding.ref);
		const note = (await read(abs(file))) ?? "";
		const wins = winsFor((await read(abs(WINS))) ?? "", file);
		const reply = await ask(ctx, PROMOTE_SYSTEM, promoteInput(clip(note, MAX_TRANSCRIPT), await topicList(), wins));
		const promotion = parsePromotion(reply);
		if (!promotion) throw new Error("promotion reply was not JSON");
		const now = new Date();
		const names: string[] = [];
		for (const topic of promotion.topics) {
			const slug = slugify(topic.slug);
			const topicFile = path.posix.join("topics", `${slug}.md`);
			const link = `[${linkText(binding.title)}](${relativeLink(topicFile, file)})`;
			await mkdir(abs("topics"), { recursive: true });
			await withLock(abs(topicFile), async () => {
				await save(abs(topicFile), appendTopic(await read(abs(topicFile)), topic, now, link));
			});
			names.push(slug);
		}
		if (promotion.win) await recordWin(promotion.win, binding);
		if (names.length || promotion.win) {
			const lines = names.length ? [`- ${stamp(now).replace("T", " ")} ${workerId(session)} topics: ${names.join(", ")}`] : [];
			if (promotion.win) lines.push(`- ${stamp(now).replace("T", " ")} ${workerId(session)} win: ${promotion.win.title}`);
			await edit(abs(file), (text) => renderNote(appendLines(parseNote(text), "Log", lines)));
		}
		return [...names.map((name) => `topics/${name}.md`), ...(promotion.win ? [WINS] : [])];
	}

	async function findRelated(binding: Binding): Promise<void> {
		related = [];
		try {
			const zg = settings.zg ?? "zg";
			if (!existsSync(abs(".zvec-grep"))) await reindex(zg, vault);
			const note = (await read(abs(taskNotePath(binding.ref)))) ?? "";
			const query = [binding.title, getSection(parseNote(note), "Goal")].join(" ").slice(0, 300);
			related = (await search(zg, vault, query, taskDir(binding.ref), 6)).slice(0, 5);
		} catch {
			related = [];
		}
	}

	async function bind(ctx: ExtensionContext, request: BindRequest): Promise<string> {
		if (!existsSync(vault)) throw new Error(`No ogham vault at ${vault}.`);
		const now = new Date();
		const { ref } = request;
		const note = abs(taskNotePath(ref));
		const created = await createOnce(note, renderTask(ref, request, now));

		if (bound && formatRef(bound.ref) !== formatRef(ref)) await updateWorker("moved");
		bound = { ref, title: request.title, role: request.role };

		const file = abs(workerNotePath(ref, session));
		const pane = process.env.HERDR_PANE_ID;
		const worker = renderWorker({
			ref,
			role: request.role,
			session,
			name: ctx.sessionManager.getSessionName(),
			intercom: process.env.PI_INTERCOM_SESSION_ID,
			pane,
			parent: request.parent,
			cwd: ctx.cwd,
			model: ctx.model?.id,
			now,
		});
		if (await createOnce(file, worker)) {
			const line = workerLine({ session, role: request.role, pane });
			await edit(note, (text) => renderNote(appendLines(parseNote(text), "Workers", [line])));
		} else {
			await edit(file, (text) => setFrontmatter(text, { role: request.role, status: "idle", updated: stamp(now) }));
		}
		if (created) await writeIndex();
		showStatus(ctx);
		void findRelated(bound);
		return `Bound to ${note} as ${request.role}.`;
	}

	async function join(ctx: ExtensionContext, text: string, role: Role, parent?: string): Promise<string> {
		const ref = parseRef(text);
		const note = ref ? abs(taskNotePath(ref)) : undefined;
		if (!ref || !note || !existsSync(note)) throw new Error(`Unknown ogham task "${text}".`);
		const heading = /^# (.+)$/m.exec(await readFile(note, "utf8"));
		const title = heading?.[1] ?? ref.slug;
		const result = await bind(ctx, { ref, title, role, parent });
		pi.appendEntry<Binding>(ENTRY, { ref, title, role });
		return result;
	}

	async function start(ctx: ExtensionContext, role: Role, task: NewTask, project?: string): Promise<string> {
		const slug = (task.link && linkSlug(task.link)) || slugify(task.title);
		const ref = { project: project ? projectName(project) : projectFor(ctx.cwd), slug };
		const result = await bind(ctx, { ...task, ref, role });
		pi.appendEntry<Binding>(ENTRY, { ref, title: task.title, role });
		return result;
	}

	async function finish(ctx: ExtensionContext): Promise<string> {
		if (!bound) throw new Error("No ogham task bound.");
		const binding = bound;
		await pending;
		showStatus(ctx, "promoting");
		let promoted: string[] = [];
		let failure = "";
		try {
			promoted = await promote(ctx, binding);
		} catch (error) {
			failure = ` Promotion failed: ${(error as Error).message}.`;
		}
		await edit(abs(taskNotePath(binding.ref)), (text) =>
			setFrontmatter(text, { status: "done", closed: stamp(new Date()), updated: stamp(new Date()) }),
		);
		await updateWorker("done");
		await writeIndex();
		refreshIndex();
		bound = undefined;
		pi.appendEntry(ENTRY, null);
		showStatus(ctx);
		const moved = promoted.length ? ` Wrote ${promoted.join(", ")}.` : "";
		return `Closed ${formatRef(binding.ref)}.${moved}${failure}`;
	}

	function joinHint(ref: string): string {
		const parent = process.env.PI_INTERCOM_SESSION_ID;
		return `Workers join with OGHAM_TASK=${ref}${parent ? ` OGHAM_PARENT=${parent}` : ""} in their environment, or ogham_task task="${ref}".`;
	}

	async function describe(): Promise<string> {
		if (!bound) return "No ogham task bound.";
		const dir = abs(path.join(taskDir(bound.ref), "workers"));
		const names = existsSync(dir) ? (await readdir(dir)).filter((name) => name.endsWith(".md")).sort() : [];
		const workers = await Promise.all(
			names.map(async (name) => `- ${workerSummary(readFrontmatter(await readFile(path.join(dir, name), "utf8")))}`),
		);
		return [`Task ${formatRef(bound.ref)}: ${bound.title} (${bound.role}).`, "Workers:", ...workers].join("\n");
	}

	pi.registerTool(
		defineTool({
			name: "ogham_task",
			label: "Ogham task",
			description: DESCRIPTION,
			parameters: Type.Object({
				title: Type.Optional(Type.String({ description: "Task title. Creates or reuses the task." })),
				task: Type.Optional(Type.String({ description: "Existing task to join, as project/slug." })),
				project: Type.Optional(Type.String({ description: "Project name. Defaults to the repo name." })),
				goal: Type.Optional(Type.String({ description: "One-line goal for a new task." })),
				link: Type.Optional(Type.String({ description: "Ticket or doc URL for a new task." })),
				role: Type.Optional(
					Type.Union([Type.Literal("orchestrator"), Type.Literal("worker")], {
						description: "orchestrator if this session drives other workers.",
					}),
				),
				done: Type.Optional(Type.Boolean({ description: "Close the bound task." })),
			}),
			async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
				const role = params.role ?? "worker";
				let text: string;
				if (params.done) text = await finish(ctx);
				else if (params.task) text = await join(ctx, params.task, role);
				else if (params.title) {
					const { title, goal, link } = params;
					text = await start(ctx, role, { title, goal, link }, params.project);
				} else text = await describe();
				if (bound) text += `\n${joinHint(formatRef(bound.ref))}`;
				return { content: [{ type: "text", text }], details: { task: bound ? formatRef(bound.ref) : undefined } };
			},
		}),
	);

	pi.registerCommand("task", {
		description: "Show, start, join, or finish the ogham task",
		handler: async (args, ctx) => {
			const input = args.trim();
			const url = findUrl(input);
			try {
				let text: string;
				if (!input) text = await describe();
				else if (input === "done") text = await finish(ctx);
				else if (input.startsWith("join ")) text = await join(ctx, input.slice(5), "worker");
				else if (url) {
					// Only the agent can read the title.
					pi.sendUserMessage(titlePrompt(url), ctx.isIdle() ? undefined : { deliverAs: "followUp" });
					text = `Looking up the title of ${url}.`;
				} else text = await start(ctx, "worker", { title: input });
				ctx.ui.notify(text, "info");
			} catch (error) {
				ctx.ui.notify((error as Error).message, "error");
			}
		},
	});

	async function quietly(ctx: ExtensionContext, work: () => Promise<unknown>): Promise<void> {
		try {
			await work();
		} catch (error) {
			ctx.ui.notify(`ogham: ${(error as Error).message}`, "warning");
		}
	}

	pi.on("session_start", async (_event, ctx) => {
		settings = readSettings();
		session = ctx.sessionManager.getSessionId();
		bound = undefined;
		related = [];
		const branch = ctx.sessionManager.getBranch();
		for (let i = branch.length - 1; i >= 0; i--) {
			const entry = branch[i];
			if (entry.type !== "custom" || entry.customType !== ENTRY) continue;
			const saved = entry.data as Binding | null;
			if (saved) await quietly(ctx, () => bind(ctx, saved));
			return;
		}
		const env = process.env.OGHAM_TASK;
		if (env) await quietly(ctx, () => join(ctx, env, "worker", process.env.OGHAM_PARENT));
	});

	pi.on("before_agent_start", async (event) => {
		if (!bound) return;
		const ref = formatRef(bound.ref);
		const note = parseNote((await read(abs(taskNotePath(bound.ref)))) ?? "");
		const known = ["Goal", "Status", "Next", "Decisions", "Findings"]
			.map((name) => [name, getSection(note, name)])
			.filter(([, body]) => body)
			.map(([name, body]) => `## ${name}\n${body}`)
			.join("\n\n");
		const notes = related.map((hit) => `From ${hit.file}:${hit.lines}\n${clip(hit.text, 800)}`).join("\n\n");
		event.systemPromptOptions.sections.ogham_task = [
			`This session works on the ogham task "${bound.title}" (${ref}) as ${bound.role}.`,
			`Task note: ${abs(taskNotePath(bound.ref))}. A side model updates it after each run; edit it only when the user asks.`,
			joinHint(ref),
			...(known ? [`<task_note>\n${clip(known, MAX_CONTEXT)}\n</task_note>`] : []),
			...(notes ? [`<related_notes>\nNotes from other tasks and topics that may help:\n\n${clip(notes, 4_000)}\n</related_notes>`] : []),
		].join("\n");
	});

	pi.on("agent_start", async (_event, ctx) => {
		await quietly(ctx, () => updateWorker("working"));
	});

	pi.on("agent_end", async (event, ctx) => {
		await quietly(ctx, () => updateWorker("idle"));
		const binding = bound;
		if (!binding || settings.curate === false) return;
		const transcript = serializeConversation(withoutBookkeeping(convertToLlm(event.messages)));
		// Runs after the turn; never blocks the user.
		pending = pending.then(async () => {
			showStatus(ctx, "curating");
			await quietly(ctx, () => curate(ctx, binding, transcript));
			showStatus(ctx);
		});
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		await Promise.race([pending, new Promise((resolve) => setTimeout(resolve, 30_000))]);
		await quietly(ctx, () => updateWorker("closed"));
	});
}
