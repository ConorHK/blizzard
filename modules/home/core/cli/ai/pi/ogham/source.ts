// Tasks from an outside list, such as tickets assigned to the user.
import type { TaskRow } from "./curate.ts";
import { linkSlug, refFromNote, slugify } from "./vault.ts";

export interface SourceItem {
	id: string;
	title: string;
	url?: string;
	updated?: string;
	status?: string;
}

const MAX_ITEMS = 300;
const oneLine = (value: string) => value.replace(/\s+/g, " ").trim();

/** Reads the source command's JSON array; skips bad entries. */
export function parseSource(text: string): SourceItem[] {
	let value: unknown;
	try {
		value = JSON.parse(text);
	} catch {
		throw new Error("task source did not print JSON");
	}
	if (!Array.isArray(value)) throw new Error("task source did not print a JSON array");
	const items: SourceItem[] = [];
	const seen = new Set<string>();
	for (const entry of value) {
		if (!entry || typeof entry !== "object") continue;
		const raw = entry as Record<string, unknown>;
		const text = (key: string) => (typeof raw[key] === "string" ? oneLine(raw[key] as string) : "");
		const id = text("id");
		const title = text("title");
		if (!id || !title || seen.has(id)) continue;
		seen.add(id);
		const url = /^https?:\/\//.test(text("url")) ? text("url") : undefined;
		items.push({ id, title, url, updated: text("updated") || undefined, status: text("status") || undefined });
		if (items.length === MAX_ITEMS) break;
	}
	return items;
}

export function sourceSlug(item: SourceItem): string {
	return (item.url && linkSlug(item.url)) || slugify(item.id);
}

/** Items with no ogham task; a task closed in ogham stays closed. */
export function untracked(items: SourceItem[], rows: TaskRow[]): SourceItem[] {
	const slugs = new Set(rows.map((row) => refFromNote(row.file)?.slug));
	return items.filter((item) => !slugs.has(sourceSlug(item)));
}

export function sourceTitle(item: SourceItem): string {
	return item.title.startsWith(item.id) ? item.title : `${item.id}: ${item.title}`;
}
