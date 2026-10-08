const FENCE_OPEN = /^(\s*)(`{3,}|~{3,})/;
const INLINE_CODE = /`([^`\n]+)`/g;
const LABEL_WIDTH = 72;

function isFenceClose(line: string, marker: string): boolean {
	const trimmed = line.trim();
	return trimmed.length >= marker.length && trimmed === marker[0].repeat(trimmed.length);
}

function dedent(line: string, indent: string): string {
	return line.startsWith(indent) ? line.slice(indent.length) : line.trimStart();
}

/** Fenced blocks first, then inline code spans. */
export function extractSnippets(markdown: string): string[] {
	const blocks: string[] = [];
	const inline: string[] = [];
	let fence: { indent: string; marker: string; body: string[] } | undefined;
	for (const line of markdown.split("\n")) {
		if (fence) {
			if (isFenceClose(line, fence.marker)) {
				blocks.push(fence.body.join("\n"));
				fence = undefined;
			} else {
				fence.body.push(dedent(line, fence.indent));
			}
			continue;
		}
		const open = line.match(FENCE_OPEN);
		if (open) {
			fence = { indent: open[1], marker: open[2], body: [] };
			continue;
		}
		for (const match of line.matchAll(INLINE_CODE)) inline.push(match[1].trim());
	}
	if (fence) blocks.push(fence.body.join("\n"));
	const seen = new Set<string>();
	return [...blocks, ...inline].filter((snippet) => {
		if (!snippet.trim() || seen.has(snippet)) return false;
		seen.add(snippet);
		return true;
	});
}

/** One-line preview of a snippet. */
export function snippetPreview(snippet: string): string {
	const lines = snippet.split("\n");
	const extra = lines.length > 1 ? ` (+${lines.length - 1} lines)` : "";
	const head = lines[0].trim();
	const room = LABEL_WIDTH - extra.length;
	const shown = head.length > room ? `${head.slice(0, room - 3)}...` : head;
	return `${shown}${extra}`;
}

export function snippetLabel(snippet: string, index: number): string {
	return `${index + 1}. ${snippetPreview(snippet)}`;
}
