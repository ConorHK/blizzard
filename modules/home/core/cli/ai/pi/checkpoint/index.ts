// checkpoint/rewind, ported from oh-my-pi (MIT).
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI, type SessionBoundaryDraft, type SessionEntry } from "@earendil-works/pi-coding-agent";

const REPORT_TYPE = "rewind-report";
const WARNING_TYPE = "checkpoint-warning";
const MAX_NUDGES = 2;

export const REWOUND_EVENT = "checkpoint:rewound";

const CHECKPOINT_DESCRIPTION = `Context checkpoint: before exploratory work; later \`rewind\`, retaining only concise report.

Use for investigations with many intermediate tool calls (\`read\`/\`grep\`/\`find\`/\`bash\`/etc.) to minimize subsequent context cost.

Rules:
- MUST \`rewind\` before yielding after starting a checkpoint.
- NEVER \`checkpoint\` while another checkpoint active.

Typical flow:
1. \`checkpoint(goal: ...)\`
2. Exploratory work
3. \`rewind(report: ...)\` with concise findings

After \`rewind\`: intermediate checkpoint messages removed from active context; replaced by report.`;

const REWIND_DESCRIPTION =
	"End the active checkpoint; rewind context to it, replacing intermediate exploration with your report.";

const SETTLE_WARNING = `<system-warning>
You are in an active checkpoint. You MUST call rewind with your investigation findings before yielding. Do NOT yield without completing the checkpoint.
</system-warning>`;

function reportMessage(report: string): string {
	return `Checkpoint called and rewound. Report retained below. Need explore again -> new \`checkpoint\`.\n\nReport:\n${report}`;
}

interface Active {
	goal: string;
	toolCallId: string;
	entryId?: string;
	nudges: number;
}

interface ToolCallBlock {
	type: string;
	id?: string;
}

export default function (pi: ExtensionAPI) {
	// Subagents skip it, as in oh-my-pi.
	if (process.env.PI_SUBAGENT_CHILD) return;

	let active: Active | undefined;
	let pendingRewind: { report: string; toolCallId: string } | undefined;
	let completed = false;

	pi.registerTool(
		defineTool({
			name: "checkpoint",
			label: "Checkpoint",
			description: CHECKPOINT_DESCRIPTION,
			parameters: Type.Object({ goal: Type.String({ description: "Investigation goal." }) }),
			async execute(toolCallId, params) {
				if (active) throw new Error("Checkpoint already active.");
				active = { goal: params.goal, toolCallId, nudges: 0 };
				completed = false;
				return {
					content: [{ type: "text", text: `Checkpoint: ${params.goal}\nFinish exploration and formulate findings.` }],
					details: { goal: params.goal, startedAt: new Date().toISOString() },
				};
			},
		}),
	);

	pi.registerTool(
		defineTool({
			name: "rewind",
			label: "Rewind",
			description: REWIND_DESCRIPTION,
			parameters: Type.Object({ report: Type.String({ description: "Investigation findings." }) }),
			async execute(toolCallId, params) {
				if (!active) {
					throw new Error(
						completed
							? "Checkpoint already completed; continue from the retained rewind report instead of calling rewind again."
							: "No active checkpoint. Create a checkpoint before calling rewind.",
					);
				}
				const report = params.report.trim();
				if (!report) throw new Error("Report cannot be empty.");
				pendingRewind = { report, toolCallId };
				return {
					content: [{ type: "text", text: "Rewind requested.\nReport captured for context replacement." }],
					details: { report, rewound: true },
				};
			},
		}),
	);

	function isToolResult(entry: SessionEntry, toolName: string): boolean {
		if (entry.type !== "message") return false;
		const message = entry.message as { role?: string; toolName?: string; isError?: boolean };
		return message.role === "toolResult" && message.toolName === toolName && !message.isError;
	}

	pi.on("session_start", (_event, ctx) => {
		active = undefined;
		pendingRewind = undefined;
		completed = false;
		// Rehydrate an unfinished checkpoint from the branch.
		const branch = ctx.sessionManager.getBranch();
		for (let i = branch.length - 1; i >= 0; i--) {
			const entry = branch[i];
			if (entry.type === "custom_message" && entry.customType === REPORT_TYPE) {
				completed = true;
				return;
			}
			if (isToolResult(entry, "checkpoint")) {
				const message = entry.message as { toolCallId: string; details?: { goal?: string } };
				active = { goal: message.details?.goal ?? "", toolCallId: message.toolCallId, entryId: entry.id, nudges: 0 };
				return;
			}
		}
	});

	pi.on("agent_start", () => {
		if (active) active.nudges = 0;
	});

	pi.on("turn_end", (event, ctx) => {
		if (active && !active.entryId) {
			const index = event.toolResults.findIndex(result => result.toolCallId === active?.toolCallId);
			if (index !== -1) active.entryId = event.toolResultEntryIds[index];
		}
		const rewind = pendingRewind;
		if (!rewind || !active) return;
		pendingRewind = undefined;
		const checkpointEntryId = active.entryId;
		active = undefined;
		completed = true;

		const entries: SessionBoundaryDraft[] = [];
		const branch = ctx.sessionManager.getBranch();
		const start = checkpointEntryId ? branch.findIndex(entry => entry.id === checkpointEntryId) : -1;
		const currentResults = new Set(event.toolResultEntryIds);
		// Keep results paired with kept calls.
		const keptCalls = new Set<string>();
		for (let i = start - 1; i >= 0; i--) {
			const entry = branch[i];
			if (entry.type !== "message") continue;
			const message = entry.message as { role?: string; content?: unknown };
			if (message.role !== "assistant" || !Array.isArray(message.content)) continue;
			for (const block of message.content as ToolCallBlock[]) if (block.type === "toolCall" && block.id) keptCalls.add(block.id);
			break;
		}
		for (const entry of start === -1 ? [] : branch.slice(start + 1)) {
			if (entry.type === "custom_message") {
				entries.push({ type: "context_edit", targetId: entry.id, replacement: null });
				continue;
			}
			if (entry.type !== "message") continue;
			const message = entry.message as { role?: string; toolCallId?: string; content?: unknown };
			if (message.role === "user") continue;
			if (entry.id === event.messageEntryId && Array.isArray(message.content)) {
				// Keep sibling calls of the rewind call.
				const kept = (message.content as ToolCallBlock[]).filter(
					block => !(block.type === "toolCall" && block.id === rewind.toolCallId),
				);
				const hasCalls = kept.some(block => block.type === "toolCall");
				entries.push({
					type: "context_edit",
					targetId: entry.id,
					replacement: hasCalls ? { content: kept as never } : null,
				});
				continue;
			}
			if (message.role === "toolResult" && message.toolCallId && keptCalls.has(message.toolCallId)) continue;
			if (message.role === "toolResult" && currentResults.has(entry.id) && message.toolCallId !== rewind.toolCallId) {
				continue;
			}
			entries.push({ type: "context_edit", targetId: entry.id, replacement: null });
		}
		entries.push({
			type: "custom_message",
			customType: REPORT_TYPE,
			content: reportMessage(rewind.report),
			display: true,
			details: { report: rewind.report, rewoundAt: new Date().toISOString() },
		});
		pi.events.emit(REWOUND_EVENT, { report: rewind.report });
		return { entries };
	});

	pi.on("agent_before_settle", () => {
		if (!active || pendingRewind || active.nudges >= MAX_NUDGES) return;
		active.nudges++;
		return {
			entries: [{ type: "custom_message", customType: WARNING_TYPE, content: SETTLE_WARNING, display: false }],
			continue: true,
		};
	});
}
