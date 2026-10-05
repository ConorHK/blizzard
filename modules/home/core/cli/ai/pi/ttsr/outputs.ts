// Ported from oh-my-pi (MIT): session/ttsr-outputs.ts.
import * as path from "node:path";
import type { TtsrMatchContext, TtsrOutput } from "./manager.ts";

export interface ToolCallLike {
	id?: string;
	name: string;
	arguments?: unknown;
}

interface ContentBlock {
	type: string;
	text?: string;
	thinking?: string;
	id?: string;
	name?: string;
	arguments?: unknown;
}

export interface AssistantLike {
	role: "assistant";
	content: ContentBlock[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

// pi's edit/write: rules see the written source.
function builtinDigest(toolName: string, args: unknown): string | undefined {
	if (!isRecord(args)) return undefined;
	if (toolName === "write" && typeof args.content === "string") return args.content;
	if (toolName === "edit" && Array.isArray(args.edits)) {
		return args.edits
			.map(edit => (isRecord(edit) && typeof edit.newText === "string" ? edit.newText : ""))
			.join("\n");
	}
	return undefined;
}

export class TtsrToolInspector {
	readonly #cwd: () => string;

	constructor(cwd: () => string) {
		this.#cwd = cwd;
	}

	matchContext(toolCall: ToolCallLike, contentIndex: number): TtsrMatchContext {
		return {
			source: "tool",
			toolName: toolCall.name,
			streamKey: toolCall.id ? `toolcall:${toolCall.id}` : `tool:${toolCall.name}:${contentIndex}`,
			filePaths: this.#filePathsFromArgs(toolCall.arguments),
		};
	}

	/** Source snapshot for edit/write, else undefined. */
	digest(toolCall: ToolCallLike): string | undefined {
		return builtinDigest(toolCall.name, toolCall.arguments);
	}

	content(toolCall: ToolCallLike): string {
		const args = toolCall.arguments;
		return this.digest(toolCall) ?? (typeof args === "string" ? args : JSON.stringify(args ?? {}));
	}

	toolCallOutput(toolCall: ToolCallLike, contentIndex: number): TtsrOutput {
		const context = this.matchContext(toolCall, contentIndex);
		const filePath = context.filePaths?.[0];
		const subject = filePath ? `\`${toolCall.name}\` call on \`${filePath}\`` : `\`${toolCall.name}\` call`;
		return { content: this.content(toolCall), context, subject };
	}

	/** Completed outputs of one assistant message. */
	outputs(message: AssistantLike): TtsrOutput[] {
		const outputs: TtsrOutput[] = [];
		const text: string[] = [];
		const thinking: string[] = [];
		for (const [index, block] of message.content.entries()) {
			if (block.type === "text" && typeof block.text === "string") text.push(block.text);
			else if (block.type === "thinking" && typeof block.thinking === "string") thinking.push(block.thinking);
			else if (block.type === "toolCall" && typeof block.name === "string") {
				outputs.push(this.toolCallOutput({ id: block.id, name: block.name, arguments: block.arguments }, index));
			}
		}
		const reply = text.join("\n\n");
		if (/\S/.test(reply)) outputs.push({ content: reply, context: { source: "text" }, subject: "reply" });
		const reasoning = thinking.join("\n\n");
		if (/\S/.test(reasoning)) {
			outputs.push({ content: reasoning, context: { source: "thinking" }, subject: "reasoning" });
		}
		return outputs;
	}

	#filePathsFromArgs(args: unknown): string[] | undefined {
		if (!isRecord(args)) return undefined;
		const rawPaths: string[] = [];
		for (const key in args) {
			const value = args[key];
			const normalizedKey = key.toLowerCase();
			if (typeof value === "string" && (normalizedKey === "path" || normalizedKey.endsWith("path"))) {
				rawPaths.push(value);
				continue;
			}
			if (Array.isArray(value) && (normalizedKey === "paths" || normalizedKey.endsWith("paths"))) {
				for (const candidate of value) if (typeof candidate === "string") rawPaths.push(candidate);
			}
		}
		const normalizedPaths = rawPaths.flatMap(filePath => this.#normalizePathCandidates(filePath));
		return normalizedPaths.length === 0 ? undefined : Array.from(new Set(normalizedPaths));
	}

	#normalizePathCandidates(rawPath: string): string[] {
		const trimmed = rawPath.trim();
		if (trimmed.length === 0) return [];
		const normalizedInput = trimmed.replaceAll("\\", "/");
		const candidates = new Set<string>([normalizedInput]);
		if (normalizedInput.startsWith("./")) candidates.add(normalizedInput.slice(2));
		const cwd = this.#cwd();
		const absolutePath = path.isAbsolute(trimmed) ? path.normalize(trimmed) : path.resolve(cwd, trimmed);
		candidates.add(absolutePath.replaceAll("\\", "/"));
		const relative = path.relative(cwd, absolutePath).replaceAll("\\", "/");
		if (relative && relative !== "." && !relative.startsWith("../") && relative !== "..") candidates.add(relative);
		return Array.from(candidates);
	}
}

export function isAssistantMessage(message: unknown): message is AssistantLike {
	const candidate = message as { role?: unknown; content?: unknown };
	return candidate?.role === "assistant" && Array.isArray(candidate.content);
}

/** Completed assistant outputs across a transcript. */
export function historyOutputs(messages: readonly unknown[], inspector: TtsrToolInspector): TtsrOutput[] {
	return messages.filter(isAssistantMessage).flatMap(message => inspector.outputs(message));
}
