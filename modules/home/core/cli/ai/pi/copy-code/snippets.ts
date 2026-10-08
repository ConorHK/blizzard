const FENCE_OPEN = /^(\s*)(`{3,}|~{3,})\s*([\w+-]*)/;
const INLINE_CODE = /`([^`\n]+)`/g;
const HEREDOC = /(?<!<)<<(?!<)(-?)\s*(['"]?)([A-Za-z_]\w*)\2/g;
const CONTINUES = /(\\|\||&&)$/;
const SHELL_LANGS = new Set(["", "bash", "sh", "shell", "zsh", "fish", "console", "terminal"]);
const LABEL_WIDTH = 72;

export interface Snippet {
	text: string;
	context?: string;
	nested?: boolean;
}

function isFenceClose(line: string, marker: string): boolean {
	const trimmed = line.trim();
	return trimmed.length >= marker.length && trimmed === marker[0].repeat(trimmed.length);
}

function dedent(line: string, indent: string): string {
	return line.startsWith(indent) ? line.slice(indent.length) : line.trimStart();
}

/** True while a shell command needs more lines. */
function isOpen(lines: string[]): boolean {
	let quote = "";
	let depth = 0;
	const heredocs: { tag: string; strip: boolean }[] = [];
	for (const line of lines) {
		if (heredocs.length > 0) {
			const { tag, strip } = heredocs[0];
			if ((strip ? line.replace(/^\t+/, "") : line) === tag) heredocs.shift();
			continue;
		}
		for (let i = 0; i < line.length; i++) {
			const ch = line[i];
			if (quote === "'") {
				if (ch === "'") quote = "";
			} else if (ch === "\\") {
				i++;
			} else if (quote) {
				if (ch === '"') quote = "";
			} else if (ch === "'" || ch === '"') {
				quote = ch;
			} else if (ch === "#" && (i === 0 || /\s/.test(line[i - 1]))) {
				break;
			} else if ("({[".includes(ch)) {
				depth++;
			} else if (")}]".includes(ch)) {
				depth = Math.max(0, depth - 1);
			}
		}
		if (!quote) {
			for (const match of line.matchAll(HEREDOC)) heredocs.push({ tag: match[3], strip: match[1] === "-" });
		}
	}
	const last = lines[lines.length - 1].trimEnd();
	return quote !== "" || depth > 0 || heredocs.length > 0 || CONTINUES.test(last);
}

/** Splits a shell block into whole commands. */
export function splitCommands(block: string): Snippet[] {
	const commands: Snippet[] = [];
	let context: string | undefined;
	let current: string[] = [];
	for (const line of block.split("\n")) {
		const trimmed = line.trim();
		if (current.length === 0) {
			if (!trimmed) {
				context = undefined;
				continue;
			}
			if (trimmed.startsWith("#")) {
				context = trimmed.replace(/^#+\s*/, "") || undefined;
				continue;
			}
		}
		current.push(line);
		if (isOpen(current)) continue;
		commands.push({ text: current.join("\n").trim(), context, nested: true });
		current = [];
	}
	if (current.length > 0) commands.push({ text: current.join("\n").trim(), context, nested: true });
	return commands;
}

function blockSnippets(text: string, lang: string): Snippet[] {
	const commands = SHELL_LANGS.has(lang.toLowerCase()) ? splitCommands(text) : [];
	if (commands.length === 0 || (commands.length === 1 && commands[0].text === text.trim())) {
		return [{ text }];
	}
	return [{ text, context: "whole block" }, ...commands];
}

/** Fenced blocks and their commands, then inline code. */
export function extractSnippets(markdown: string): Snippet[] {
	const blocks: Snippet[] = [];
	const inline: Snippet[] = [];
	let fence: { indent: string; marker: string; lang: string; body: string[] } | undefined;
	for (const line of markdown.split("\n")) {
		if (fence) {
			if (isFenceClose(line, fence.marker)) {
				blocks.push(...blockSnippets(fence.body.join("\n"), fence.lang));
				fence = undefined;
			} else {
				fence.body.push(dedent(line, fence.indent));
			}
			continue;
		}
		const open = line.match(FENCE_OPEN);
		if (open) {
			fence = { indent: open[1], marker: open[2], lang: open[3], body: [] };
			continue;
		}
		for (const match of line.matchAll(INLINE_CODE)) inline.push({ text: match[1].trim() });
	}
	if (fence) blocks.push(...blockSnippets(fence.body.join("\n"), fence.lang));
	const seen = new Set<string>();
	return [...blocks, ...inline].filter(({ text }) => {
		if (!text.trim() || seen.has(text)) return false;
		seen.add(text);
		return true;
	});
}

function fit(text: string, width: number): string {
	return text.length > width ? `${text.slice(0, width - 3)}...` : text;
}

/** One-line preview of snippet text. */
export function snippetPreview(text: string, width = LABEL_WIDTH): string {
	const lines = text.split("\n");
	const extra = lines.length > 1 ? ` (+${lines.length - 1} lines)` : "";
	return fit(lines[0].trim(), width - extra.length) + extra;
}

export function snippetLabel(snippet: Snippet, index: number): string {
	const indent = snippet.nested ? "  " : "";
	const context = snippet.context ? `${fit(snippet.context, LABEL_WIDTH / 2)} | ` : "";
	return `${indent}${index + 1}. ${context}${snippetPreview(snippet.text, LABEL_WIDTH - context.length)}`;
}
