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

export const linkText = (text: string) => text.replace(/[[\]]/g, "\\$&");

export function relativeLink(from: string, to: string): string {
	return path.posix.relative(path.posix.dirname(from), to);
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

/** Inverse of taskNotePath. */
export function refFromNote(file: string): TaskRef | undefined {
	const match = /^projects\/([^/]+)\/([^/]+)\/\2\.md$/.exec(file);
	return match ? { project: match[1], slug: match[2] } : undefined;
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

export function yamlValue(value: string | string[]): string {
	// JSON arrays are YAML flow lists.
	if (Array.isArray(value)) return JSON.stringify(value);
	if (/^[A-Za-z][A-Za-z0-9_./-]*$/.test(value) && !/^(true|false|null|yes|no|on|off)$/i.test(value)) return value;
	if (/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$/.test(value)) return value;
	return JSON.stringify(value);
}

export function readList(value: string | undefined): string[] {
	if (!value?.startsWith("[")) return [];
	try {
		const parsed: unknown = JSON.parse(value);
		return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : [];
	} catch {
		return [];
	}
}

export function frontmatter(fields: Record<string, string | string[] | undefined>): string {
	const lines = Object.entries(fields)
		.filter((entry): entry is [string, string | string[]] => entry[1] !== undefined)
		.map(([key, value]) => `${key}: ${yamlValue(value)}`);
	return `---\n${lines.join("\n")}\n---\n`;
}

/** Sets flat frontmatter keys, keeping the rest. */
export function setFrontmatter(text: string, updates: Record<string, string | string[]>): string {
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
	return `${fields}# ${task.title}\n\n${link}## Goal\n\n${task.goal ? `${task.goal}\n\n` : ""}## Status\n\n## Next\n\n## Log\n\n## Workers\n`;
}

/** Drops trailing punctuation and unmatched closing brackets. */
function trimUrl(url: string): string {
	let trimmed = url.replace(/[.,;:!?'"`>\]]+$/, "");
	while (trimmed.endsWith(")") && trimmed.split("(").length < trimmed.split(")").length) {
		trimmed = trimmed.slice(0, -1).replace(/[.,;:!?'"`>\]]+$/, "");
	}
	return trimmed;
}

export function findUrl(text: string): string | undefined {
	const url = /https?:\/\/\S+/.exec(text)?.[0];
	return url ? trimUrl(url) : undefined;
}

// Skips version segments like v2 or python3.
const TICKET_ID = /^[a-z]+-\d+$|^[a-z]+\d{4,}$/i;

/** Ticket ID from the URL, so retitles reuse it. */
export function linkSlug(url: string): string | undefined {
	let segments: string[];
	try {
		segments = new URL(url).pathname.split("/").filter(Boolean).map(decodeURIComponent);
	} catch {
		return undefined;
	}
	const id = [...segments].reverse().find((segment) => TICKET_ID.test(segment));
	if (id) return slugify(id);
	// Bare numbers repeat across repos, so keep their parents.
	const number = segments.findIndex((segment) => /^\d+$/.test(segment));
	return number === -1 ? undefined : slugify(segments.slice(Math.max(0, number - 2), number + 1).join("-"));
}

export const TITLE_PROMPT_START = "Start an ogham task for ";

export function titlePrompt(url: string): string {
	return [
		`${TITLE_PROMPT_START}${url}.`,
		`Look up its ID and title with your tools, then call ogham_task with title "<ID>: <title>" and link "${url}".`,
		"If you cannot read it, use the last part of the URL as the title.",
		"Then reply with the task name only.",
	].join("\n");
}

export function workerLine(info: Pick<WorkerInfo, "session" | "role" | "pane">): string {
	const id = workerId(info.session);
	return `- [${id}](workers/${id}.md) ${info.role}${info.pane ? `, pane ${info.pane}` : ""}`;
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
	return `${fields}# ${info.name ?? workerId(info.session)}\n`;
}

export function readFrontmatter(text: string): Record<string, string> {
	const match = /^---\n([\s\S]*?)\n---\n/.exec(text);
	const fields: Record<string, string> = {};
	for (const line of match?.[1].split("\n") ?? []) {
		const pair = /^([\w-]+): (.*)$/.exec(line);
		if (!pair) continue;
		const value = pair[2];
		fields[pair[1]] = value.startsWith('"') ? unquote(value) : value;
	}
	return fields;
}

/** Hand edits can break the quoting; keep the raw text then. */
function unquote(value: string): string {
	try {
		const parsed: unknown = JSON.parse(value);
		return typeof parsed === "string" ? parsed : value;
	} catch {
		return value;
	}
}

/** One line per worker note. */
export function workerSummary(fields: Record<string, string>): string {
	const parts = [fields.session ? workerId(fields.session) : "?", fields.role, fields.status];
	if (fields.pane) parts.push(`pane ${fields.pane}`);
	if (fields.intercom) parts.push(`intercom ${fields.intercom}`);
	if (fields.updated) parts.push(`updated ${fields.updated}`);
	return parts.filter(Boolean).join(" ");
}
