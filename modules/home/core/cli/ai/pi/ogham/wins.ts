// Win records, one file each under wins/.
import * as path from "node:path";
import type { TaskRow } from "./curate.ts";
import { frontmatter, linkText, readFrontmatter, readList, relativeLink, slugify } from "./vault.ts";

export const CATEGORIES = ["reliability", "latency", "cost", "toil", "security", "quality", "launch", "other"] as const;
export type Category = (typeof CATEGORIES)[number];
export const ROLES = ["led", "contributed"] as const;
export type WinRole = (typeof ROLES)[number];

export const ARTIFACT_KINDS = ["tickets", "sims", "code", "docs"] as const;
export type ArtifactKind = (typeof ARTIFACT_KINDS)[number];
export type Artifacts = Record<ArtifactKind, string[]>;

export type ArtifactRules = [ArtifactKind, RegExp][];

// Public hosts only; org hosts come from settings.
const DEFAULT_RULES: Record<ArtifactKind, string[]> = {
	tickets: ["^https://github\\.com/[^/]+/[^/]+/issues/\\d+", "^https://[^/]+\\.atlassian\\.net/browse/[A-Z][A-Z0-9]*-\\d+"],
	sims: [],
	code: [
		"^https://github\\.com/[^/]+/[^/]+/(pull/\\d+|commit/[0-9a-f]{7,40})",
		"^https://gitlab\\.com/[^#?]+?/-/(merge_requests/\\d+|commit/[0-9a-f]{7,40})",
	],
	docs: ["^https://docs\\.google\\.com/(document|spreadsheets|presentation)/d/"],
};

/** Settings rules first; bad patterns come back unthrown. */
export function compileRules(extra: Partial<Record<ArtifactKind, string[]>> = {}): { rules: ArtifactRules; bad: string[] } {
	const rules: ArtifactRules = [];
	const bad: string[] = [];
	for (const source of [extra, DEFAULT_RULES]) {
		for (const kind of ARTIFACT_KINDS) {
			for (const pattern of source[kind] ?? []) {
				try {
					rules.push([kind, new RegExp(pattern)]);
				} catch {
					bad.push(pattern);
				}
			}
		}
	}
	return { rules, bad };
}

const DEFAULTS = compileRules().rules;

export const noArtifacts = (): Artifacts => ({ tickets: [], sims: [], code: [], docs: [] });

/** Sorts URLs by rule; a match is the canonical URL, except for docs. */
export function artifactsOf(urls: string[], rules: ArtifactRules = DEFAULTS): Artifacts {
	const found = noArtifacts();
	const seen = new Set<string>();
	for (const raw of urls) {
		const url = raw.replace(/[.,;:!?'"`>\]]+$/, "");
		for (const [kind, rule] of rules) {
			const match = rule.exec(url);
			if (!match) continue;
			const canonical = kind === "docs" ? url.replace(/#.*$/, "") : match[0];
			// One SIM item can show up on several hosts.
			const key = kind === "sims" ? `sim:${canonical.split("/").at(-1)}` : canonical;
			if (!seen.has(key)) found[kind].push(canonical);
			seen.add(key);
			break;
		}
	}
	return found;
}

export function urlsIn(text: string): string[] {
	return [...text.matchAll(/https?:\/\/[^\s"'<>()[\]`]+/g)].map((match) => match[0]);
}

/** Union per kind; both sides are already canonical. */
export function mergeArtifacts(a: Artifacts, b: Artifacts): Artifacts {
	const merged = noArtifacts();
	for (const kind of ARTIFACT_KINDS) {
		const seen = new Set<string>();
		for (const url of [...a[kind], ...b[kind]]) {
			const key = kind === "sims" ? `sim:${url.split("/").at(-1)}` : url;
			if (!seen.has(key)) merged[kind].push(url);
			seen.add(key);
		}
	}
	return merged;
}

export interface Win {
	title: string;
	summary: string;
	impact: string;
	evidence: string[];
	category?: Category;
	role?: WinRole;
	metric?: string;
	before?: string;
	after?: string;
	scope?: string;
}

export interface WinRecord extends Win {
	file: string;
	date: string;
	task?: string;
	initiative?: string;
	measured?: string;
	result?: string;
	impactAfter?: string;
	artifacts: Artifacts;
}

export const FOLLOW_UP_DAYS = 14;
export const STALE_DAYS = 21;
export const WINS_MARKER = "<!-- ogham builds this from wins/; edits here are lost. -->";

export function winFile(date: string, title: string, n = 1): string {
	return path.posix.join("wins", `${date}-${slugify(title)}${n > 1 ? `-${n}` : ""}.md`);
}

export function renderWinFile(record: WinRecord, taskTitle?: string): string {
	const set = (value?: string) => value || undefined;
	const fields = frontmatter({
		type: "win",
		date: record.date,
		task: set(record.task),
		initiative: set(record.initiative),
		category: set(record.category),
		role: set(record.role),
		metric: set(record.metric),
		before: set(record.before),
		after: set(record.after),
		scope: set(record.scope),
		measured: set(record.measured),
		result: set(record.result),
		impact_after: set(record.impactAfter),
		...Object.fromEntries(ARTIFACT_KINDS.map((kind) => [kind, record.artifacts[kind].length ? record.artifacts[kind] : undefined])),
	});
	const lines = [`# ${record.title}`, ""];
	if (record.summary) lines.push(record.summary, "");
	lines.push(`- Impact: ${record.impact}`);
	if (record.evidence.length) lines.push(`- Evidence: ${record.evidence.join(", ")}`);
	if (record.task) lines.push(`- Task: [${linkText(taskTitle ?? record.task)}](${relativeLink(record.file, record.task)})`);
	if (record.measured && record.result) lines.push(`- Measured ${record.measured}: ${record.result}`);
	return `${fields}${lines.join("\n")}\n`;
}

/** Appends the measured line to a win file. */
export function addMeasured(text: string, day: string, result: string): string {
	return `${text.replace(/\n*$/, "")}\n- Measured ${day}: ${result}\n`;
}

const pick = <T extends string>(values: readonly T[], value?: string): T | undefined =>
	values.includes(value as T) ? (value as T) : undefined;

export function parseWinFile(file: string, text: string): WinRecord | undefined {
	const fields = readFrontmatter(text);
	if (fields.type !== "win") return undefined;
	const body = text.replace(/^---\n[\s\S]*?\n---\n/, "");
	const line = (name: string) => new RegExp(`^- ${name}: (.+)$`, "m").exec(body)?.[1].trim() ?? "";
	const title = /^# (.+)$/m.exec(body)?.[1].trim() ?? path.posix.basename(file, ".md");
	const summary = body
		.replace(/^# .+\n/, "")
		.split(/\n- Impact: /)[0]
		.trim();
	const value = (key: string) => fields[key] || undefined;
	return {
		file,
		date: fields.date ?? "",
		title,
		summary,
		impact: line("Impact"),
		evidence: line("Evidence") ? line("Evidence").split(/,\s*/) : [],
		task: value("task"),
		initiative: value("initiative"),
		category: pick(CATEGORIES, fields.category),
		role: pick(ROLES, fields.role),
		metric: value("metric"),
		before: value("before"),
		after: value("after"),
		scope: value("scope"),
		measured: value("measured"),
		result: value("result"),
		impactAfter: value("impact_after"),
		artifacts: Object.fromEntries(ARTIFACT_KINDS.map((kind) => [kind, readList(fields[kind])])) as Artifacts,
	};
}

/** Entries in the old single-file wins.md format. */
export function legacyWins(text: string): WinRecord[] {
	const records: WinRecord[] = [];
	for (const block of text.split(/^(?=## )/m)) {
		const head = /^## (\d{4}-\d{2}-\d{2}) (.+)$/m.exec(block);
		if (!head || !/^- Impact: /m.test(block)) continue;
		const line = (name: string) => new RegExp(`^- ${name}: (.+)$`, "m").exec(block)?.[1].trim() ?? "";
		const [date, title] = [head[1], head[2].trim()];
		const summary = block.slice(head[0].length).split(/\n- Impact: /)[0].trim();
		records.push({
			file: winFile(date, title),
			date,
			title,
			summary,
			impact: line("Impact"),
			evidence: line("Evidence") ? line("Evidence").split(/,\s*/) : [],
			task: /^- Task: .*\]\(([^)\s]+)\)$/m.exec(block)?.[1],
			artifacts: noArtifacts(),
		});
	}
	return records;
}

const ARTIFACT_NAMES: Record<ArtifactKind, string> = { tickets: "ticket", sims: "SIM", code: "code change", docs: "doc" };

export function artifactCounts(artifacts: Artifacts): string {
	return ARTIFACT_KINDS.filter((kind) => artifacts[kind].length)
		.map((kind) => `${artifacts[kind].length} ${ARTIFACT_NAMES[kind]}${artifacts[kind].length > 1 ? "s" : ""}`)
		.join(", ");
}

function details(record: WinRecord): string {
	const parts = [record.category, record.role].filter(Boolean).join(", ");
	const impact = record.impact.length > 120 ? `${record.impact.slice(0, 119)}...` : record.impact;
	const metric = record.metric && record.after ? `${record.metric}: ${record.before || "?"} -> ${record.after}` : record.result || impact;
	const counts = artifactCounts(record.artifacts);
	const text = [parts, metric].filter(Boolean).join(". ");
	return counts ? `${text} (${counts})`.trim() : text;
}

/** wins.md: wins grouped by initiative. */
export function renderWinsIndex(records: WinRecord[]): string {
	const newest = (items: WinRecord[]) => items.reduce((best, item) => (item.date > best ? item.date : best), "");
	const groups = new Map<string, WinRecord[]>();
	for (const record of records) {
		const key = record.initiative ?? "";
		groups.set(key, [...(groups.get(key) ?? []), record]);
	}
	const keys = [...groups.keys()].sort((a, b) => (!a ? 1 : !b ? -1 : newest(groups.get(b)!).localeCompare(newest(groups.get(a)!))));
	const parts = ["# Wins", "", WINS_MARKER, ""];
	for (const key of keys) {
		parts.push(`## ${key || "No initiative"}`, "");
		for (const record of groups.get(key)!.sort((a, b) => b.date.localeCompare(a.date))) {
			const more = details(record);
			parts.push(`- ${record.date} [${linkText(record.title)}](${record.file})${more ? `: ${more}` : ""}`);
		}
		parts.push("");
	}
	return parts.join("\n").replace(/\n+$/, "\n");
}

/** Wins already recorded for one task, for the curator. */
export function winsFor(records: WinRecord[], task: string): string {
	return records
		.filter((record) => record.task === task)
		.map((record) => `- ${record.date} ${record.title}: ${record.impact}`)
		.join("\n");
}

export function parseMeasure(text: string): { metric: string; before: string; after: string } | undefined {
	const match = /^(.+?):\s*(.+?)\s*->\s*(.+)$/.exec(text.trim());
	return match ? { metric: match[1].trim(), before: match[2].trim(), after: match[3].trim() } : undefined;
}

function dayOf(stamp?: string): number | undefined {
	const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(stamp ?? "");
	return match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / 86_400_000 : undefined;
}

export function addDays(day: string, days: number): string {
	return new Date(((dayOf(day) ?? 0) + days) * 86_400_000).toISOString().slice(0, 10);
}

const snoozed = (until: string | undefined, today: string) =>
	until === "never" || (dayOf(until) ?? -Infinity) > (dayOf(today) ?? 0);

const olderThan = (stamp: string | undefined, today: string, days: number) => {
	const day = dayOf(stamp);
	return day !== undefined && (dayOf(today) ?? 0) - day >= days;
};

const short = (title: string) => (title.length > 60 ? `${title.slice(0, 59)}...` : title);

export interface FollowUp {
	kind: "impact-win" | "impact-task" | "close";
	label: string;
	file: string;
	title: string;
}

/** Shipped work old enough to measure, still unmeasured. */
export function impactDue(wins: WinRecord[], tasks: TaskRow[], today: string, max: number): FollowUp[] {
	const unmeasured = wins
		.filter((win) => !win.measured && !win.after && olderThan(win.date, today, FOLLOW_UP_DAYS) && !snoozed(win.impactAfter, today))
		.sort((a, b) => a.date.localeCompare(b.date))
		.map((win): FollowUp => ({ kind: "impact-win", label: `Impact: ${short(win.title)}`, file: win.file, title: win.title }));
	const withWins = new Set(wins.map((win) => win.task));
	const shipped = tasks
		.filter(
			(task) =>
				(task.status === "review" || task.status === "done") &&
				!withWins.has(task.file) &&
				olderThan(task.closed || task.updated, today, FOLLOW_UP_DAYS) &&
				!snoozed(task.impactAfter, today),
		)
		.sort((a, b) => (a.closed || a.updated).localeCompare(b.closed || b.updated))
		.map((task): FollowUp => ({ kind: "impact-task", label: `Impact: ${task.project}: ${short(task.title)}`, file: task.file, title: task.title }));
	return [...unmeasured, ...shipped].slice(0, max);
}

/** Open tasks that look finished or abandoned. */
export function closeDue(tasks: TaskRow[], today: string, max: number): FollowUp[] {
	return tasks
		.filter((task) => task.status !== "done" && !snoozed(task.closeAfter, today) && (task.resolved || olderThan(task.updated, today, STALE_DAYS)))
		.sort((a, b) => Number(!a.resolved) - Number(!b.resolved) || a.updated.localeCompare(b.updated))
		.slice(0, max)
		.map((task) => ({ kind: "close", label: `Close: ${task.project}: ${short(task.title)}`, file: task.file, title: task.title }));
}
