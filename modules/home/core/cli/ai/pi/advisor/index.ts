// Turn reviewer, ported from oh-my-pi (MIT).
import { existsSync, readFileSync } from "node:fs";
import * as path from "node:path";
import { Type } from "@earendil-works/pi-ai";
import {
	type AgentSession,
	createAgentSession,
	createExtensionRuntime,
	defineTool,
	type ExtensionAPI,
	type ExtensionContext,
	getAgentDir,
	type ResourceLoader,
	type SessionBoundaryDraft,
	SessionManager,
} from "@earendil-works/pi-coding-agent";
import { contextFiles, watchdogFiles } from "./context.ts";
import { type DeliveryChannel, deliveryChannel, EmissionGuard, normalizeNote, SEVERITY_RANK, type Severity } from "./guard.ts";
import { ADVISOR_NOTE_TYPE, MAX_REPLAY_CHARS, renderAdvisory, renderUpdate } from "./transcript.ts";

const REWOUND_EVENT = "checkpoint:rewound";
const MAX_FAILURES = 3;
// Strict sync never hangs a session forever.
const STRICT_WAIT_MS = 10 * 60_000;
const LEVELS = "off|minimal|low|medium|high|xhigh|max";

interface AdvisorSettings {
	enabled: boolean;
	model?: string;
	reviewMode: "turn" | "agent-end";
	reviewInterval: number;
	maxNotesPerUpdate: number;
	immuneTurns: number;
	syncBacklog: "off" | "strict";
	tools: string[];
}

const DEFAULTS: AdvisorSettings = {
	enabled: true,
	reviewMode: "turn",
	reviewInterval: 1,
	maxNotesPerUpdate: 4,
	immuneTurns: 3,
	syncBacklog: "off",
	tools: ["read", "grep", "find", "ls"],
};

const ACK_SENT = "Delivered.";
const ACK_DEFERRED = "Queued for the end of the turn. Do not re-raise.";
const ACK_SUPPRESSED = {
	empty: "Dropped: empty note.",
	noise: "Dropped: nothing actionable.",
	duplicate: "Dropped: already raised.",
	"rate-limit": "Dropped: this update's advice budget is spent.",
} as const;

function prompt(name: string): string {
	return readFileSync(new URL(`./prompts/${name}.md`, import.meta.url), "utf8").trim();
}

interface Pending {
	key: string;
	note: string;
	severity: Severity;
}

interface Collected {
	channel: DeliveryChannel;
	draft: SessionBoundaryDraft;
}

export default function (pi: ExtensionAPI) {
	// Subagents run unadvised, as in oh-my-pi.
	if (process.env.PI_SUBAGENT_CHILD) return;

	let settings: AdvisorSettings = { ...DEFAULTS };
	let sessionOverride: boolean | undefined;
	let active = false;
	let generation = 0;
	let lastCtx: ExtensionContext | undefined;
	let advisor: { session: AgentSession; label: string } | undefined;
	let guard = new EmissionGuard(DEFAULTS.maxNotesPerUpdate);
	let cursor: string | undefined;
	let deferred: Pending[] = [];
	let reviewWip = false;
	let reviewing: Promise<void> | undefined;
	let queuedWip: boolean | undefined;
	let eligible = 0;
	let turnsSinceInterrupt = Number.POSITIVE_INFINITY;
	let autoResumeSuppressed = false;
	let advisorDriven = false;
	let failures = 0;
	let settleCollector: Collected[] | undefined;
	const stats = { reviews: 0, delivered: 0, suppressed: 0 };

	function readSettings(): AdvisorSettings {
		const file = path.join(getAgentDir(), "advisor.json");
		if (!existsSync(file)) return { ...DEFAULTS };
		try {
			return { ...DEFAULTS, ...(JSON.parse(readFileSync(file, "utf8")) as Partial<AdvisorSettings>) };
		} catch (error) {
			lastCtx?.ui.notify(`advisor.json is invalid: ${error instanceof Error ? error.message : String(error)}`, "warning");
			return { ...DEFAULTS };
		}
	}

	function systemPrompt(ctx: ExtensionContext): string {
		const parts = [prompt("system").replace("{{max_notes_per_update}}", String(settings.maxNotesPerUpdate))];
		const trusted = ctx.isProjectTrusted();
		const files = contextFiles(ctx.cwd, getAgentDir(), trusted);
		if (files.length > 0) {
			parts.push(
				[
					"<project-context>",
					"Context files: user's standing project instructions (AGENTS.md etc.); binding on driving agent. Enforce; flag drift immediately; NEVER advise against mandates.",
					...files.map(file => `<file path="${file.path}">\n${file.content}\n</file>`),
					"</project-context>",
				].join("\n"),
			);
		}
		for (const file of watchdogFiles(ctx.cwd, getAgentDir(), trusted)) {
			parts.push(`Especially pay attention to:\n<attention>\n${file.content}\n</attention>`);
		}
		return parts.join("\n\n");
	}

	function resolveModel(ctx: ExtensionContext) {
		if (settings.model) {
			const match = new RegExp(`^(.*?)(?::(${LEVELS}))?$`).exec(settings.model);
			const spec = match?.[1] ?? settings.model;
			const slash = spec.indexOf("/");
			const model = slash > 0 ? ctx.modelRegistry.find(spec.slice(0, slash), spec.slice(slash + 1)) : undefined;
			if (model) return { model, thinkingLevel: (match?.[2] as typeof ctx.thinkingLevel) ?? ctx.thinkingLevel };
			ctx.ui.notify(`Advisor model ${settings.model} not found; using session model.`, "warning");
		}
		return { model: ctx.model, thinkingLevel: ctx.thinkingLevel };
	}

	const adviseTool = defineTool({
		name: "advise",
		label: "Advise",
		description: prompt("advise-tool"),
		parameters: Type.Object({
			note: Type.String({ description: "One concrete, terse note for the watched agent." }),
			severity: Type.Optional(
				Type.Union([Type.Literal("nit"), Type.Literal("concern"), Type.Literal("blocker")], {
					description: "nit (default), concern, or blocker.",
				}),
			),
		}),
		async execute(_toolCallId, params) {
			const severity: Severity = params.severity ?? "nit";
			const rank = SEVERITY_RANK[severity];
			const key = normalizeNote(params.note);
			const result = (text: string) => ({ content: [{ type: "text" as const, text }], details: { severity } });
			if (reviewWip && rank < SEVERITY_RANK.blocker) {
				const decision = guard.admit(params.note, { rank, pending: true });
				if (!decision.accepted) {
					stats.suppressed++;
					return result(ACK_SUPPRESSED[decision.reason ?? "duplicate"]);
				}
				deferred = deferred.filter(item => item.key !== decision.displacedKey && item.key !== key);
				deferred.push({ key, note: params.note, severity });
				return result(ACK_DEFERRED);
			}
			deferred = deferred.filter(item => item.key !== key);
			const decision = guard.admit(params.note, { rank, pending: false });
			if (!decision.accepted) {
				stats.suppressed++;
				return result(ACK_SUPPRESSED[decision.reason ?? "duplicate"]);
			}
			deliver(params.note, severity);
			return result(ACK_SENT);
		},
	});

	async function ensureSession(ctx: ExtensionContext): Promise<AgentSession> {
		if (advisor) return advisor.session;
		const { model, thinkingLevel } = resolveModel(ctx);
		if (!model) throw new Error("no model for the advisor");
		const text = systemPrompt(ctx);
		const resourceLoader: ResourceLoader = {
			getExtensions: () => ({ extensions: [], errors: [], runtime: createExtensionRuntime() }),
			getSkills: () => ({ skills: [], diagnostics: [] }),
			getPrompts: () => ({ prompts: [], diagnostics: [] }),
			getThemes: () => ({ themes: [], diagnostics: [] }),
			getAgentsFiles: () => ({ agentsFiles: [] }),
			getSystemPrompt: () => text,
			getSystemPromptSource: () => undefined,
			getAppendSystemPrompt: () => [],
			getAppendSystemPromptSources: () => [],
			extendResources: () => {},
			reload: async () => {},
		};
		const { session } = await createAgentSession({
			cwd: ctx.cwd,
			sessionManager: SessionManager.inMemory(ctx.cwd),
			model,
			thinkingLevel,
			// The allowlist must name custom tools too.
			tools: [...settings.tools, "advise"],
			customTools: [adviseTool],
			resourceLoader,
		});
		advisor = { session, label: `${model.provider}/${model.id}${thinkingLevel ? `:${thinkingLevel}` : ""}` };
		return session;
	}

	function resetAdvisor(): void {
		const old = advisor;
		advisor = undefined;
		if (old) void old.session.abort().finally(() => old.session.dispose());
		guard = new EmissionGuard(settings.maxNotesPerUpdate);
		deferred = [];
	}

	function terminalAnswer(ctx: ExtensionContext): boolean {
		if (ctx.hasPendingMessages()) return false;
		const leaf = ctx.sessionManager.getLeafEntry() as { type?: string; message?: { role?: string; stopReason?: string; content?: unknown } } | undefined;
		const message = leaf?.type === "message" ? leaf.message : undefined;
		if (message?.role !== "assistant" || message.stopReason !== "stop") return false;
		return !(Array.isArray(message.content) && message.content.some((block: { type: string }) => block.type === "toolCall"));
	}

	function deliver(note: string, severity: Severity): void {
		const ctx = lastCtx;
		if (!ctx) return;
		const collecting = settleCollector !== undefined;
		const streaming = !collecting && !ctx.isIdle();
		const channel = deliveryChannel({
			severity,
			autoResumeSuppressed,
			streaming,
			terminalAnswer: settings.reviewMode === "turn" && terminalAnswer(ctx),
			immune: turnsSinceInterrupt < settings.immuneTurns,
		});
		const message = {
			customType: ADVISOR_NOTE_TYPE,
			content: renderAdvisory(note, severity),
			display: true,
			details: { note, severity, advisor: advisor?.label },
		};
		stats.delivered++;
		if (channel === "steer") turnsSinceInterrupt = 0;
		if (settleCollector) {
			settleCollector.push({ channel, draft: { type: "custom_message", ...message } });
			return;
		}
		if (streaming) {
			void pi.sendMessage(message, { deliverAs: "steer" });
		} else if (channel === "steer") {
			advisorDriven = true;
			void pi.sendMessage(message, { triggerTurn: true });
		} else {
			// Shown now; sent with the next prompt.
			void pi.sendMessage(message);
		}
	}

	function flushDeferred(): void {
		const pending = deferred;
		deferred = [];
		for (const item of pending) {
			guard.markRouted(item.note);
			deliver(item.note, item.severity);
		}
	}

	async function reviewOnce(wip: boolean): Promise<void> {
		const ctx = lastCtx;
		if (!ctx || !active) return;
		const started = generation;
		const branch = ctx.sessionManager.getBranch();
		let start = 0;
		let maxChars: number | undefined = MAX_REPLAY_CHARS;
		if (cursor) {
			const index = branch.findIndex(entry => entry.id === cursor);
			if (index === -1) resetAdvisor();
			else {
				start = index + 1;
				maxChars = undefined;
			}
		}
		const slice = branch.slice(start);
		if (slice.length === 0) return;
		cursor = branch[branch.length - 1].id;
		const update = renderUpdate(slice, wip, maxChars);
		if (!update) return;
		try {
			const session = await ensureSession(ctx);
			if (started !== generation) return;
			guard.beginUpdate();
			reviewWip = wip;
			await session.prompt(update, { source: "extension" });
			const last = session.messages.at(-1) as { role?: string; stopReason?: string; errorMessage?: string } | undefined;
			if (last?.role === "assistant" && last.stopReason === "error") throw new Error(last.errorMessage ?? "review failed");
			failures = 0;
			stats.reviews++;
		} catch (error) {
			failures++;
			ctx.ui.notify(`Advisor review failed: ${error instanceof Error ? error.message : String(error)}`, "warning");
			if (failures >= MAX_FAILURES) {
				active = false;
				ctx.ui.notify("Advisor stopped after 3 failed reviews.", "error");
			}
			return;
		} finally {
			reviewWip = false;
		}
		if (!wip && started === generation) flushDeferred();
	}

	function scheduleReview(wip: boolean): void {
		if (reviewing) {
			// A final review supersedes queued partial ones.
			queuedWip = queuedWip === undefined ? wip : queuedWip && wip;
			return;
		}
		reviewing = (async () => {
			let next: boolean | undefined = wip;
			try {
				while (next !== undefined) {
					queuedWip = undefined;
					await reviewOnce(next);
					next = queuedWip;
				}
			} finally {
				reviewing = undefined;
				queuedWip = undefined;
			}
		})();
	}

	function activate(ctx: ExtensionContext): void {
		active = (sessionOverride ?? settings.enabled) && failures < MAX_FAILURES;
		cursor = ctx.sessionManager.getLeafId() ?? undefined;
	}

	pi.on("session_start", (_event, ctx) => {
		generation++;
		lastCtx = ctx;
		settings = readSettings();
		resetAdvisor();
		failures = 0;
		eligible = 0;
		turnsSinceInterrupt = Number.POSITIVE_INFINITY;
		autoResumeSuppressed = false;
		advisorDriven = false;
		activate(ctx);
	});

	pi.on("session_compact", () => {
		resetAdvisor();
		cursor = undefined;
	});

	pi.events.on(REWOUND_EVENT, () => {
		resetAdvisor();
		cursor = lastCtx?.sessionManager.getLeafId() ?? undefined;
	});

	pi.on("agent_start", (_event, ctx) => {
		lastCtx = ctx;
		autoResumeSuppressed = false;
	});

	pi.on("turn_end", (event, ctx) => {
		lastCtx = ctx;
		if (!active) return;
		turnsSinceInterrupt++;
		const message = event.message as { stopReason?: string; content?: unknown };
		if (message.stopReason === "aborted") autoResumeSuppressed = true;
		const final =
			message.stopReason !== "aborted" &&
			!(Array.isArray(message.content) && message.content.some((block: { type: string }) => block.type === "toolCall"));
		// Advisor-started runs are not reviewed.
		if (advisorDriven) return;
		if (settings.reviewMode === "agent-end" && !final) return;
		eligible++;
		if (eligible % Math.max(1, settings.reviewInterval) !== 0) return;
		scheduleReview(!final);
	});

	pi.on("agent_before_settle", async () => {
		if (!active || settings.syncBacklog !== "strict" || !reviewing) return;
		settleCollector = [];
		let timer: ReturnType<typeof setTimeout> | undefined;
		await Promise.race([reviewing, new Promise(resolve => (timer = setTimeout(resolve, STRICT_WAIT_MS)))]);
		clearTimeout(timer);
		const collected = settleCollector;
		settleCollector = undefined;
		if (collected.length === 0) return;
		const resume = collected.some(item => item.channel === "steer");
		if (resume) advisorDriven = true;
		return { entries: collected.map(item => item.draft), continue: resume };
	});

	pi.on("agent_settled", () => {
		advisorDriven = false;
		if (!reviewing && deferred.length > 0) flushDeferred();
	});

	pi.on("session_shutdown", () => {
		generation++;
		resetAdvisor();
	});

	pi.registerCommand("advisor", {
		description: "Advisor: on, off, status, dump",
		handler: async (args, ctx) => {
			lastCtx = ctx;
			const sub = args.trim();
			if (sub === "" || sub === "on" || sub === "off") {
				sessionOverride = sub === "" ? !active : sub === "on";
				failures = 0;
				if (!sessionOverride) resetAdvisor();
				activate(ctx);
				ctx.ui.notify(`Advisor ${active ? "on" : "off"} for this session.`, "info");
				return;
			}
			if (sub === "status") {
				const usage = advisor?.session.getSessionStats();
				const model = advisor?.label ?? (settings.model || "session model");
				ctx.ui.notify(
					[
						`Advisor ${active ? "on" : "off"} (${settings.reviewMode}, every ${settings.reviewInterval}, sync ${settings.syncBacklog})`,
						`Model: ${model}`,
						`Reviews ${stats.reviews}, delivered ${stats.delivered}, suppressed ${stats.suppressed}`,
						usage ? `Tokens ${usage.tokens.total}, cost $${usage.cost.toFixed(3)}` : "No advisor session yet.",
					].join("\n"),
					"info",
				);
				return;
			}
			if (sub === "dump") {
				const messages = advisor?.session.messages ?? [];
				const text = messages
					.map(raw => {
						const message = raw as { role?: string; content?: unknown };
						const content =
							typeof message.content === "string"
								? message.content
								: Array.isArray(message.content)
									? message.content
											.map((block: { type: string; text?: string; name?: string; arguments?: unknown }) =>
												block.type === "text" ? block.text : block.type === "toolCall" ? `[${block.name}] ${JSON.stringify(block.arguments)}` : "",
											)
											.filter(Boolean)
											.join("\n")
									: "";
						return `## ${message.role}\n${content}`;
					})
					.join("\n\n");
				await ctx.ui.editor("Advisor transcript", text || "(empty)");
				return;
			}
			ctx.ui.notify("Usage: /advisor [on|off|status|dump]", "warning");
		},
	});
}
