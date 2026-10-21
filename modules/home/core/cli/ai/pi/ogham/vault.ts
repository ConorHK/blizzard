import { existsSync } from "node:fs";
import * as path from "node:path";

export type Role = "orchestrator" | "worker";

export interface TaskRef {
	project: string;
	slug: string;
}

export interface WorkerInfo {
	ref: TaskRef;
	role: Role;
	session: string;
	name?: string;
	intercom?: string;
	pane?: string;
	parent?: string;
	cwd: string;
	model?: string;
	now: Date;
}

export function slugify(text: string): string {
	const slug = text
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+/, "")
		.slice(0, 60)
		.replace(/-+$/, "");
	return slug || "task";
}

export function projectName(text: string): string {
	return text.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^[.-]+/, "") || "misc";
}

export function parseRef(text: string): TaskRef | undefined {
	const parts = text.trim().split("/");
	if (parts.length !== 2 || !parts[0] || !parts[1]) return undefined;
	return { project: projectName(parts[0]), slug: slugify(parts[1]) };
}

export function formatRef(ref: TaskRef): string {
	return `${ref.project}/${ref.slug}`;
}

/** Repo root name, else the cwd name. */
export function projectFor(cwd: string): string {
	for (let dir = path.resolve(cwd); ; dir = path.dirname(dir)) {
		if (existsSync(path.join(dir, ".git")) || existsSync(path.join(dir, ".jj"))) {
			return projectName(path.basename(dir));
		}
		if (path.dirname(dir) === dir) return projectName(path.basename(path.resolve(cwd)));
	}
}

export function taskDir(ref: TaskRef): string {
	return path.posix.join("projects", ref.project, ref.slug);
}

export function taskNotePath(ref: TaskRef): string {
	return path.posix.join(taskDir(ref), `${ref.slug}.md`);
}

export function workerId(session: string): string {
	return session.slice(0, 8);
}

export function workerNotePath(ref: TaskRef, session: string): string {
	return path.posix.join(taskDir(ref), "workers", `${workerId(session)}.md`);
}

/** Local time, minute precision. */
export function stamp(date: Date): string {
	const pad = (n: number) => String(n).padStart(2, "0");
	return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function yamlValue(value: string): string {
	if (/^[A-Za-z][A-Za-z0-9_./-]*$/.test(value) && !/^(true|false|null|yes|no|on|off)$/i.test(value)) return value;
	if (/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$/.test(value)) return value;
	return JSON.stringify(value);
}

function frontmatter(fields: Record<string, string | undefined>): string {
	const lines = Object.entries(fields)
		.filter((entry): entry is [string, string] => entry[1] !== undefined)
		.map(([key, value]) => `${key}: ${yamlValue(value)}`);
	return `---\n${lines.join("\n")}\n---\n`;
}

/** Sets flat frontmatter keys, keeping the rest. */
export function setFrontmatter(text: string, updates: Record<string, string>): string {
	const match = /^---\n([\s\S]*?)\n---\n/.exec(text);
	if (!match) return frontmatter(updates) + text;
	const lines = match[1].split("\n");
	for (const [key, value] of Object.entries(updates)) {
		const line = `${key}: ${yamlValue(value)}`;
		const index = lines.findIndex((existing) => existing.startsWith(`${key}:`));
		if (index === -1) lines.push(line);
		else lines[index] = line;
	}
	return `---\n${lines.join("\n")}\n---\n${text.slice(match[0].length)}`;
}

export interface NewTask {
	title: string;
	goal?: string;
	link?: string;
}

export function renderTask(ref: TaskRef, task: NewTask, now: Date): string {
	const fields = frontmatter({
		type: "task",
		project: ref.project,
		status: "active",
		link: task.link,
		created: stamp(now),
	});
	const link = task.link ? `${task.link}\n\n` : "";
	return `${fields}# ${task.title}\n\n${link}## Goal\n\n${task.goal ?? ""}\n\n## Log\n\n## Workers\n\n`;
}

export function findUrl(text: string): string | undefined {
	return /https?:\/\/\S+/.exec(text)?.[0];
}

/** Asks the agent to name a task from a URL. */
export function titlePrompt(input: string, url: string): string {
	const rest = input.replace(url, " ").replace(/\s+/g, " ").trim();
	return [
		`Start an ogham task for ${url}.`,
		`Look up its ID and title with your tools, then call ogham_task with title "<ID>: <title>" and link "${url}".`,
		"If you cannot read it, use the last part of the URL as the title.",
		...(rest ? [`The user added: "${rest}". Pass it as goal if it states one.`] : []),
		"Then reply with the task name only.",
	].join("\n");
}

/** Appended to the task note; keep Workers last. */
export function workerLine(info: Pick<WorkerInfo, "session" | "role" | "pane">): string {
	const id = workerId(info.session);
	return `- [${id}](workers/${id}.md) ${info.role}${info.pane ? `, pane ${info.pane}` : ""}\n`;
}

export function renderWorker(info: WorkerInfo): string {
	const fields = frontmatter({
		type: "worker",
		task: formatRef(info.ref),
		role: info.role,
		status: "idle",
		session: info.session,
		name: info.name,
		intercom: info.intercom,
		pane: info.pane,
		parent: info.parent,
		cwd: info.cwd,
		model: info.model,
		started: stamp(info.now),
		updated: stamp(info.now),
	});
	return `${fields}# ${info.name ?? workerId(info.session)}\n\n## Log\n\n`;
}

export function readFrontmatter(text: string): Record<string, string> {
	const match = /^---\n([\s\S]*?)\n---\n/.exec(text);
	const fields: Record<string, string> = {};
	for (const line of match?.[1].split("\n") ?? []) {
		const pair = /^([\w-]+): (.*)$/.exec(line);
		if (!pair) continue;
		const value = pair[2];
		fields[pair[1]] = value.startsWith('"') ? (JSON.parse(value) as string) : value;
	}
	return fields;
}

/** One line per worker note. */
export function workerSummary(fields: Record<string, string>): string {
	const parts = [fields.session ? workerId(fields.session) : "?", fields.role, fields.status];
	if (fields.pane) parts.push(`pane ${fields.pane}`);
	if (fields.intercom) parts.push(`intercom ${fields.intercom}`);
	if (fields.updated) parts.push(`updated ${fields.updated}`);
	return parts.filter(Boolean).join(" ");
}

export function logLine(now: Date, text: string): string {
	const time = stamp(now).slice(11);
	const line = text.replace(/\s+/g, " ").trim();
	return `- ${time} ${line.length > 160 ? `${line.slice(0, 157)}...` : line}\n`;
}

interface TextBlock {
	type: string;
	text?: string;
}

interface MessageLike {
	role?: string;
	content?: unknown;
}

/** First non-empty line of the last reply. */
export function replyHeadline(messages: readonly unknown[]): string | undefined {
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i] as MessageLike;
		if (message?.role !== "assistant" || !Array.isArray(message.content)) continue;
		const text = (message.content as TextBlock[])
			.filter((block) => block.type === "text" && block.text)
			.map((block) => block.text)
			.join("\n");
		const line = text
			.split("\n")
			.map((part) => part.trim())
			.find(Boolean);
		if (line) return line;
	}
	return undefined;
}
