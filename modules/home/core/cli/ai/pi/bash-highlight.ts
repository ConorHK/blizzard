// Syntax-highlights bash tool calls, heredoc bodies included.
import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { getLanguageFromPath, highlightCode } from "@earendil-works/pi-coding-agent";

const HEREDOC = /(?<!<)<<-?\s*(['"]?)([A-Za-z_]\w*)\1/;
const TARGET = /(?:>>?|\btee(?:\s+-a)?)\s*['"]?([^\s'";|&)]+)/;
const INTERPRETER = /\b(python3?|node|bash|sh|zsh)\b[^<]*<</;
const INTERPRETER_LANG: Record<string, string> = {
	python: "python",
	python3: "python",
	node: "javascript",
	bash: "bash",
	sh: "bash",
	zsh: "bash",
};
const CACHE_LIMIT = 64;

function bodyLanguage(line: string): string | undefined {
	const target = line.match(TARGET)?.[1];
	const fromTarget = target?.endsWith(".nix") ? "nix" : target && getLanguageFromPath(target);
	const interpreter = line.match(INTERPRETER)?.[1];
	return fromTarget || (interpreter ? INTERPRETER_LANG[interpreter] : undefined);
}

function highlightCommand(command: string): string {
	const lines = command.split("\n");
	const out: string[] = [];
	let start = 0;
	for (let i = 0; i < lines.length; i++) {
		const match = lines[i].match(HEREDOC);
		if (!match) continue;
		out.push(...highlightCode(lines.slice(start, i + 1).join("\n"), "bash"));
		let end = lines.findIndex((line, j) => j > i && line.trim() === match[2]);
		// Unterminated while args still stream in.
		if (end === -1) end = lines.length;
		if (end > i + 1) {
			out.push(...highlightCode(lines.slice(i + 1, end).join("\n"), bodyLanguage(lines[i])));
		}
		start = end;
		i = end - 1;
	}
	if (start < lines.length) out.push(...highlightCode(lines.slice(start).join("\n"), "bash"));
	return out.join("\n");
}

// Spinner redraws repeat the same command.
const cache = new Map<string, string>();

function cachedHighlight(theme: Theme, text: string): string {
	const key = `${theme.name}\0${text}`;
	let result = cache.get(key);
	if (result === undefined) {
		result = highlightCommand(text);
		if (cache.size >= CACHE_LIMIT) cache.delete(cache.keys().next().value as string);
		cache.set(key, result);
	}
	return result;
}

// tool-display paints the command via fg("accent").
function highlightingTheme(theme: Theme, command: string): Theme {
	const wrapped = Object.create(theme) as Theme;
	wrapped.fg = (color, text) =>
		color === "accent" && (text === command || text.endsWith(` ${command}`))
			? cachedHighlight(theme, text)
			: theme.fg(color, text);
	return wrapped;
}

export default function (pi: ExtensionAPI) {
	pi.registerToolRenderer((toolName, next) => {
		const base = next();
		if (toolName !== "bash" || !base?.renderCall) return base;
		const renderCall = base.renderCall;
		return {
			...base,
			renderCall(args, theme, context) {
				const command = typeof args?.command === "string" ? args.command : "";
				return renderCall(args, command.trim() ? highlightingTheme(theme, command) : theme, context);
			},
		};
	});
}
