// Side-model prompts and how replies apply.
import * as path from "node:path";
import { appendLines, getSection, type Note, parseNote, renderNote, setSection } from "./note.ts";
import { TITLE_PROMPT_START } from "./vault.ts";

export interface Win {
	title: string;
	summary: string;
	impact: string;
	evidence: string[];
}

export interface Curation {
	status?: string;
	next?: string[];
	decisions: string[];
	findings: string[];
	links: { url: string; label: string }[];
	log?: string;
	state?: "active" | "blocked" | "review";
	win?: Win;
}

export interface TopicUpdate {
	slug: string;
	title: string;
	summary?: string;
	entries: string[];
}

export interface Promotion {
	topics: TopicUpdate[];
	win?: Win;
}

const WIN_RULES = `A win is a result with value someone outside the team would recognize: a change merged or deployed, an incident or ticket resolved, a measurable gain in speed, cost, reliability, or toil, a launch, or a doc or tool others adopted.
Local progress is not a win: drafts, passing local tests, investigations without an outcome, posted but unmerged reviews.
Write wins for a performance review: what changed, who benefits, and by how much when the transcript says. Cite evidence (review, ticket, pipeline, or metric URLs) from the transcript only. Never invent numbers.`;

export const CURATE_SYSTEM = `You keep a task note current for a software engineer. You get the note and the transcript of the latest agent run on the task.

Reply with one JSON object and nothing else:
{
  "status": "2 to 4 sentences: where the task stands now",
  "next": ["open next step", "..."],
  "decisions": ["new decision and its reason"],
  "findings": ["new durable fact, with its source path or URL"],
  "links": [{"url": "...", "label": "short label"}],
  "log": "one line on what this run changed, or empty",
  "state": "active | blocked | review",
  "win": null
}

Rules:
- Use only facts in the note or transcript. Never guess.
- Ignore ogham bookkeeping: binding the task, join commands, worker status, and this note itself. They are never findings, status, or log.
- status replaces the old one. next replaces the old list: keep items still open, drop finished ones, add new ones.
- decisions, findings, and links hold only new entries not already in the note. Findings are facts worth knowing next time: root causes, where code lives, commands that work, gotchas.
- links: pick only from the candidate URLs, and only ones worth returning to.
- log is empty when the run changed nothing.
- state is blocked when waiting on someone else, review when work awaits review or deploy.
- win: set {"title", "summary", "impact", "evidence": [...]} only when this run reached a milestone that counts as a win, and it is not in the wins already recorded.
${WIN_RULES}`;

export const PROMOTE_SYSTEM = `A task just closed. Move its durable knowledge into topic notes, and record its win.

Reply with one JSON object and nothing else:
{
  "topics": [{"slug": "kebab-case", "title": "Topic", "summary": "one line, for new topics only", "entries": ["fact with source"]}],
  "win": null
}

Rules:
- Topics are subjects that outlive the task: a system, service, tool, or practice. Reuse an existing topic slug when one fits.
- Entries are findings and decisions useful beyond this task. Keep sources.
- Keep only facts that stay true after the task ends: how a system works, where code lives, root causes, commands, gotchas.
- Skip open work, status, next steps, ticket relationships (which epic a task belongs to), and ogham bookkeeping. An empty topics list is fine.
- win: set {"title", "summary", "impact", "evidence": [...]} when the task as a whole delivered a win not already recorded.
${WIN_RULES}`;

export function curateInput(note: string, transcript: string, candidates: string[], wins: string): string {
	return [
		`<note>\n${note}\n</note>`,
		`<wins_recorded>\n${wins || "none"}\n</wins_recorded>`,
		`<candidate_urls>\n${candidates.join("\n") || "none"}\n</candidate_urls>`,
		`<transcript>\n${transcript}\n</transcript>`,
	].join("\n\n");
}

export function promoteInput(note: string, topics: string, wins: string): string {
	return [
		`<note>\n${note}\n</note>`,
		`<topics>\n${topics || "none"}\n</topics>`,
		`<wins_recorded>\n${wins || "none"}\n</wins_recorded>`,
	].join("\n\n");
}

/** Keeps head and tail of long text. */
export function clip(text: string, max: number): string {
	if (text.length <= max) return text;
	const head = Math.floor(max / 4);
	return `${text.slice(0, head)}\n[... ${text.length - max} chars cut ...]\n${text.slice(text.length - (max - head))}`;
}

interface Block {
	type: string;
	name?: string;
	text?: string;
}

interface LlmMessage {
	role: string;
	content: unknown;
	toolName?: string;
}

/** Drops ogham's own calls and prompts. */
export function withoutBookkeeping<T>(messages: T[]): T[] {
	const kept: T[] = [];
	for (const item of messages) {
		const message = item as unknown as LlmMessage;
		if (message.role === "toolResult" && message.toolName === "ogham_task") continue;
		if (message.role === "user") {
			const text = typeof message.content === "string" ? message.content : ((message.content as Block[])[0]?.text ?? "");
			if (text.startsWith(TITLE_PROMPT_START)) continue;
		}
		if (message.role === "assistant" && Array.isArray(message.content)) {
			const content = (message.content as Block[]).filter((block) => !(block.type === "toolCall" && block.name === "ogham_task"));
			if (content.length === 0) continue;
			kept.push({ ...(item as object), content } as T);
			continue;
		}
		kept.push(item);
	}
	return kept;
}

export function candidateUrls(text: string, known: string): string[] {
	const urls = new Set<string>();
	for (const match of text.matchAll(/https?:\/\/[^\s"'<>()[\]`]+/g)) {
		const url = match[0].replace(/[.,;:!?]+$/, "");
		if (!known.includes(url)) urls.add(url);
	}
	return [...urls].slice(0, 40);
}

function jsonObject(text: string): Record<string, unknown> | undefined {
	const start = text.indexOf("{");
	const end = text.lastIndexOf("}");
	if (start === -1 || end <= start) return undefined;
	const raw = text.slice(start, end + 1);
	// Models sometimes leave raw newlines in strings.
	for (const candidate of [raw, raw.replace(/[\u0000-\u001f]+/g, " ")]) {
		try {
			const value = JSON.parse(candidate);
			if (value && typeof value === "object") return value as Record<string, unknown>;
		} catch {}
	}
	return undefined;
}

const oneLine = (value: string) => value.replace(/\s+/g, " ").trim();

export const linkText = (text: string) => text.replace(/[[\]]/g, "\\$&");

function strings(value: unknown): string[] {
	return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string").map(oneLine).filter(Boolean) : [];
}

function parseWin(value: unknown): Win | undefined {
	if (!value || typeof value !== "object") return undefined;
	const win = value as Record<string, unknown>;
	const text = (key: string) => (typeof win[key] === "string" ? oneLine(win[key] as string) : "");
	if (!text("title") || !text("impact")) return undefined;
	return { title: text("title"), summary: text("summary"), impact: text("impact"), evidence: strings(win.evidence) };
}

export function parseCuration(text: string): Curation | undefined {
	const value = jsonObject(text);
	if (!value) return undefined;
	const links = Array.isArray(value.links)
		? value.links
				.filter((link): link is { url: string; label?: string } => typeof link?.url === "string")
				.map((link) => ({ url: link.url.trim(), label: oneLine(link.label ?? "") || link.url.trim() }))
		: [];
	const state = typeof value.state === "string" ? value.state.trim() : "";
	return {
		status: typeof value.status === "string" ? value.status.trim() : undefined,
		next: Array.isArray(value.next) ? strings(value.next) : undefined,
		decisions: strings(value.decisions),
		findings: strings(value.findings),
		links,
		log: typeof value.log === "string" ? oneLine(value.log) : undefined,
		state: state === "active" || state === "blocked" || state === "review" ? state : undefined,
		win: parseWin(value.win),
	};
}

export function parsePromotion(text: string): Promotion | undefined {
	const value = jsonObject(text);
	if (!value) return undefined;
	const topics = Array.isArray(value.topics)
		? value.topics
				.filter((topic): topic is Record<string, unknown> => !!topic && typeof topic === "object")
				.map((topic) => ({
					slug: typeof topic.slug === "string" ? topic.slug : "",
					title: typeof topic.title === "string" ? oneLine(topic.title) : "",
					summary: typeof topic.summary === "string" ? oneLine(topic.summary) : undefined,
					entries: strings(topic.entries),
				}))
				.filter((topic) => topic.slug && topic.title && topic.entries.length > 0)
		: [];
	return { topics, win: parseWin(value.win) };
}

/** Minute stamp, local time. */
function minute(date: Date): string {
	const pad = (n: number) => String(n).padStart(2, "0");
	return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function applyCuration(text: string, update: Curation, now: Date, worker: string): string {
	const day = minute(now).slice(0, 10);
	let note: Note = parseNote(text);
	if (update.status) note = setSection(note, "Status", update.status);
	if (update.next) note = setSection(note, "Next", update.next.map((item) => `- [ ] ${item}`).join("\n"));
	note = appendLines(
		note,
		"Decisions",
		update.decisions.map((item) => `- ${day} ${item}`),
	);
	note = appendLines(
		note,
		"Findings",
		update.findings.map((item) => `- ${day} ${item}`),
	);
	const known = getSection(note, "Links");
	note = appendLines(
		note,
		"Links",
		update.links.filter((link) => !known.includes(link.url)).map((link) => `- [${link.label}](${link.url})`),
	);
	if (update.log) note = appendLines(note, "Log", [`- ${minute(now)} ${worker} ${update.log}`]);
	if (update.win) note = appendLines(note, "Log", [`- ${minute(now)} ${worker} win: ${update.win.title}`]);
	return renderNote(note);
}

export function renderWin(win: Win, now: Date, task: { title: string; file: string }): string {
	const lines = [`## ${minute(now).slice(0, 10)} ${win.title}`, ""];
	if (win.summary) lines.push(win.summary, "");
	lines.push(`- Impact: ${win.impact}`);
	if (win.evidence.length) lines.push(`- Evidence: ${win.evidence.join(", ")}`);
	lines.push(`- Task: [${linkText(task.title)}](${task.file})`, "");
	return lines.join("\n");
}

/** Recorded wins that link to the task. */
export function winsFor(wins: string, file: string): string {
	return wins
		.split(/^(?=## )/m)
		.filter((entry) => entry.includes(`](${file})`))
		.join("")
		.trim();
}

export function appendTopic(existing: string | undefined, topic: TopicUpdate, now: Date, taskLink: string): string {
	const day = minute(now).slice(0, 10);
	const entries = topic.entries.map((entry) => `- ${entry} (${taskLink})`).join("\n");
	if (!existing) {
		const summary = topic.summary ? `${topic.summary}\n\n` : "";
		return `---\ntype: topic\n---\n# ${topic.title}\n\n${summary}## ${day}\n\n${entries}\n`;
	}
	const body = existing.replace(/\n+$/, "\n");
	const last = body.match(/^## (.+)$/gm)?.at(-1);
	return last === `## ${day}` ? `${body}${entries}\n` : `${body}\n## ${day}\n\n${entries}\n`;
}

export interface TaskRow {
	project: string;
	file: string;
	title: string;
	status: string;
	updated: string;
	next?: string;
}

export function firstOpen(note: string): string | undefined {
	return /^- \[ \] (.+)$/m.exec(getSection(parseNote(note), "Next"))?.[1];
}

export function renderIndex(rows: TaskRow[], hasWins: boolean): string {
	const open = rows.filter((row) => row.status !== "done");
	const done = rows.filter((row) => row.status === "done");
	const line = (row: TaskRow) => {
		const next = row.next && row.status !== "done" ? `. Next: ${row.next}` : "";
		return `- [${linkText(row.title)}](${row.file}) ${row.status}, ${row.updated}${next}`;
	};
	const parts = ["# Tasks", ""];
	for (const project of [...new Set(open.map((row) => row.project))].sort()) {
		parts.push(`## ${project}`, "");
		for (const row of open.filter((item) => item.project === project).sort((a, b) => b.updated.localeCompare(a.updated))) {
			parts.push(line(row));
		}
		parts.push("");
	}
	if (done.length) {
		parts.push("## Done", "");
		for (const row of done.sort((a, b) => b.updated.localeCompare(a.updated))) parts.push(line(row));
		parts.push("");
	}
	if (hasWins) parts.push("Wins: [wins.md](wins.md)", "");
	return parts.join("\n").replace(/\n+$/, "\n");
}

export function relativeLink(from: string, to: string): string {
	return path.posix.relative(path.posix.dirname(from), to);
}
