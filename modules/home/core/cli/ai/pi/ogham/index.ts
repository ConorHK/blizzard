// Tracks the current task and its workers in ogham.
import { existsSync } from "node:fs";
import { appendFile, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import * as path from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI, type ExtensionContext, withFileMutationQueue } from "@earendil-works/pi-coding-agent";
import {
	formatRef,
	logLine,
	parseRef,
	projectFor,
	projectName,
	readFrontmatter,
	renderTask,
	renderWorker,
	replyHeadline,
	type Role,
	setFrontmatter,
	slugify,
	stamp,
	type TaskRef,
	taskDir,
	taskNotePath,
	workerLine,
	workerNotePath,
	workerSummary,
} from "./vault.ts";

const ENTRY = "ogham-task";

interface Binding {
	ref: TaskRef;
	title: string;
	role: Role;
}

interface BindRequest extends Binding {
	goal?: string;
	parent?: string;
}

const DESCRIPTION = `Bind this session to an ogham task, a markdown note in the user's notes repo.

Call it when the user says which task they are working on. Pass title to create or reuse a task in the current repo's project. Pass task ("project/slug") to join a task another session created. Pass done to close the bound task. Pass nothing to list the task's workers with their status, pane, and intercom id.

Each session gets its own worker note under the task, updated automatically.`;

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_CHILD) return;

	const vault = process.env.OGHAM_VAULT ?? path.join(homedir(), "ogham");
	let bound: Binding | undefined;
	let session = "";

	const abs = (relative: string) => path.join(vault, relative);
	const workerFile = () => (bound ? abs(workerNotePath(bound.ref, session)) : undefined);

	async function edit(file: string, change: (text: string) => string): Promise<void> {
		await withFileMutationQueue(file, async () => {
			const text = await readFile(file, "utf8");
			await writeFile(file, change(text));
		});
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

	async function updateWorker(status: string, log?: string): Promise<void> {
		const file = workerFile();
		if (!file || !existsSync(file)) return;
		const now = new Date();
		const updates: Record<string, string> = { status, updated: stamp(now) };
		// pi-intercom sets it in its own session_start.
		const intercom = process.env.PI_INTERCOM_SESSION_ID;
		if (intercom) updates.intercom = intercom;
		await edit(file, (text) => setFrontmatter(text, updates) + (log ? logLine(now, log) : ""));
	}

	function showStatus(ctx: ExtensionContext): void {
		ctx.ui.setStatus("ogham", bound ? `task: ${formatRef(bound.ref)}` : undefined);
	}

	async function bind(ctx: ExtensionContext, request: BindRequest): Promise<string> {
		if (!existsSync(vault)) throw new Error(`No ogham vault at ${vault}.`);
		const now = new Date();
		const { ref } = request;
		await createOnce(abs(taskNotePath(ref)), renderTask(ref, request.title, request.goal, now));

		if (bound && formatRef(bound.ref) !== formatRef(ref)) await updateWorker("moved", `moved to ${formatRef(ref)}`);
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
			// O_APPEND keeps parallel joins intact.
			await appendFile(abs(taskNotePath(ref)), workerLine({ session, role: request.role, pane }));
		} else {
			await edit(file, (text) => setFrontmatter(text, { role: request.role, status: "idle", updated: stamp(now) }));
		}
		showStatus(ctx);
		return `Bound to ${abs(taskNotePath(ref))} as ${request.role}.`;
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

	async function start(ctx: ExtensionContext, title: string, role: Role, project?: string, goal?: string): Promise<string> {
		const ref = { project: project ? projectName(project) : projectFor(ctx.cwd), slug: slugify(title) };
		const result = await bind(ctx, { ref, title, role, goal });
		pi.appendEntry<Binding>(ENTRY, { ref, title, role });
		return result;
	}

	async function finish(ctx: ExtensionContext): Promise<string> {
		if (!bound) throw new Error("No ogham task bound.");
		const ref = bound.ref;
		await edit(abs(taskNotePath(ref)), (text) => setFrontmatter(text, { status: "done", closed: stamp(new Date()) }));
		await updateWorker("done", "task done");
		bound = undefined;
		pi.appendEntry(ENTRY, null);
		showStatus(ctx);
		return `Closed ${formatRef(ref)}.`;
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
				else if (params.title) text = await start(ctx, params.title, role, params.project, params.goal);
				else text = await describe();
				if (bound) text += `\n${joinHint(formatRef(bound.ref))}`;
				return { content: [{ type: "text", text }], details: { task: bound ? formatRef(bound.ref) : undefined } };
			},
		}),
	);

	pi.registerCommand("task", {
		description: "Show, start, join, or finish the ogham task",
		handler: async (args, ctx) => {
			const input = args.trim();
			try {
				let text: string;
				if (!input) text = await describe();
				else if (input === "done") text = await finish(ctx);
				else if (input.startsWith("join ")) text = await join(ctx, input.slice(5), "worker");
				else text = await start(ctx, input, "worker");
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
		session = ctx.sessionManager.getSessionId();
		bound = undefined;
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

	pi.on("before_agent_start", (event) => {
		if (!bound) return;
		const ref = formatRef(bound.ref);
		event.systemPromptOptions.sections.ogham_task = [
			`This session works on the ogham task "${bound.title}" (${ref}) as ${bound.role}.`,
			`Task note: ${abs(taskNotePath(bound.ref))}. Append decisions and results under its "## Log" heading.`,
			joinHint(ref),
		].join("\n");
	});

	pi.on("agent_start", async (_event, ctx) => {
		await quietly(ctx, () => updateWorker("working"));
	});

	pi.on("agent_end", async (event, ctx) => {
		await quietly(ctx, () => updateWorker("idle", replyHeadline(event.messages)));
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		await quietly(ctx, () => updateWorker("closed"));
	});
}
