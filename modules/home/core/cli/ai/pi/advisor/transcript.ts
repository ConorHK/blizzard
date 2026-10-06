// Primary session entries as advisor updates.

export const ADVISOR_NOTE_TYPE = "advisor-note";
export const WIP_MARKER = "[in progress - more steps follow]";

const MAX_TOOL_RESULT = 2_500;
const MAX_TOOL_ARGS = 2_000;
const MAX_CONTEXT_MESSAGE = 400;
// Bounds a replay after reset.
export const MAX_REPLAY_CHARS = 80_000;

interface Block {
	type: string;
	text?: string;
	name?: string;
	arguments?: unknown;
}

interface EntryLike {
	type: string;
	customType?: string;
	content?: unknown;
	summary?: string;
	message?: { role?: string; content?: unknown; toolName?: string; isError?: boolean; command?: string; output?: string };
}

function elide(text: string, max: number): string {
	if (text.length <= max) return text;
	return `${text.slice(0, max)}\n[elided ${text.length - max} chars]`;
}

function blocks(content: unknown): Block[] {
	if (typeof content === "string") return [{ type: "text", text: content }];
	return Array.isArray(content) ? (content as Block[]) : [];
}

function textOf(content: unknown): string {
	return blocks(content)
		.map(block => (block.type === "text" ? (block.text ?? "") : block.type === "image" ? "[image]" : ""))
		.filter(Boolean)
		.join("\n");
}

function renderEntry(entry: EntryLike): string | undefined {
	if (entry.type === "custom_message") {
		if (entry.customType === ADVISOR_NOTE_TYPE) return undefined;
		// The report replaces pruned exploration.
		if (entry.customType === "rewind-report") return `**Checkpoint report:**\n${textOf(entry.content)}`;
		return `**Context (${entry.customType}):** ${elide(textOf(entry.content), MAX_CONTEXT_MESSAGE)}`;
	}
	if (entry.type === "compaction" || entry.type === "branch_summary") {
		return entry.summary ? `**Summary of earlier work:**\n${elide(entry.summary, MAX_TOOL_RESULT)}` : undefined;
	}
	if (entry.type !== "message" || !entry.message) return undefined;
	const message = entry.message;
	switch (message.role) {
		case "user": {
			const text = textOf(message.content);
			return text ? `**User:**\n${text}` : undefined;
		}
		case "assistant": {
			const parts: string[] = [];
			// Replayed reasoning trips Anthropic's extraction classifier.
			for (const block of blocks(message.content)) {
				if (block.type === "text" && block.text?.trim()) {
					parts.push(`**Agent:**\n${block.text}`);
				} else if (block.type === "toolCall") {
					parts.push(`**Tool call \`${block.name}\`:**\n${elide(JSON.stringify(block.arguments ?? {}), MAX_TOOL_ARGS)}`);
				}
			}
			return parts.length > 0 ? parts.join("\n\n") : undefined;
		}
		case "toolResult": {
			const label = message.isError ? "Tool error" : "Tool result";
			return `**${label} \`${message.toolName ?? "?"}\`:**\n${elide(textOf(message.content), MAX_TOOL_RESULT)}`;
		}
		case "bashExecution":
			return `**User shell \`${message.command ?? ""}\`:**\n${elide(message.output ?? "", MAX_TOOL_RESULT)}`;
		default:
			return undefined;
	}
}

export function renderUpdate(entries: readonly EntryLike[], wip: boolean, maxChars?: number): string | undefined {
	let body = entries
		.map(renderEntry)
		.filter((part): part is string => part !== undefined)
		.join("\n\n");
	if (!body.trim()) return undefined;
	if (maxChars !== undefined && body.length > maxChars) body = `[earlier updates elided]\n\n${body.slice(-maxChars)}`;
	const update = `### Session update\n\n${body}`;
	return wip ? `${update}\n\n---\n\n${WIP_MARKER}` : update;
}

function escapeXml(text: string): string {
	return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export function renderAdvisory(note: string, severity: string): string {
	return `<advisory severity="${severity}" guidance="weigh, don't blindly obey">\n${escapeXml(note)}\n</advisory>`;
}
