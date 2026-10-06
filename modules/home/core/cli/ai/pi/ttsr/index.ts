// TTSR and /omfg, ported from oh-my-pi (MIT).
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type {
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
	SessionBoundaryDraft,
} from "@earendil-works/pi-coding-agent";
import { buildSessionContext, getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { astGrepMatcher } from "./ast.ts";
import { chatJudge, classifierJudge, type Judge, judgeRules } from "./judge.ts";
import { DEFAULT_SETTINGS, log, TtsrManager, type TtsrSettings } from "./manager.ts";
import {
	extractGeneratedRuleJson,
	type ParsedGeneratedRule,
	parseGeneratedRule,
	validateParsedRuleAgainstAssistantHistory,
	withPath,
} from "./omfg-rule.ts";
import { historyOutputs, isAssistantMessage, TtsrToolInspector } from "./outputs.ts";
import { render } from "./prompts.ts";
import { buildRule, type Rule, type RuleFrontmatter, type RuleLevel } from "./rule.ts";

const AST_GREP = process.env.PI_TTSR_AST_GREP ?? "@astGrep@";
const STATE_TYPE = "ttsr-state";
const MESSAGE_TYPE = "ttsr-injection";
const DRAFT_TYPE = "omfg-draft";
const MAX_ATTEMPTS = 3;
// Opus-class judges answer within this.
const JUDGE_WAIT_MS = 30_000;
const MAX_TRANSCRIPT_CHARS = 400_000;
const PROJECT_OPTION = "This project (.pi/rules)";
const AMEND_OPTION = "Amend with feedback...";

interface StateEntry {
	injected?: string[];
}

interface DraftEntry {
	status: string;
	content: string;
}

type Source = "text" | "thinking" | "tool";

export default function (pi: ExtensionAPI) {
	let settings: TtsrSettings = { ...DEFAULT_SETTINGS };
	const astMatch = astGrepMatcher(AST_GREP);
	let manager = new TtsrManager(() => settings, astMatch);
	let inspector = new TtsrToolInspector(() => process.cwd());
	let generation = 0;
	let pendingInterrupt: Rule[] | undefined;
	let pendingRetry: Rule[] | undefined;
	const deferredProse = new Map<string, Rule>();
	const toolReminders = new Map<string, Rule[]>();
	const turnReminders: Rule[] = [];
	const pendingJudgments = new Set<Promise<void>>();
	let settleWarnings: SessionBoundaryDraft[] | undefined;
	const warned = new Set<string>();
	let notify: (message: string, type?: "info" | "warning" | "error") => void = () => {};

	log.warn = (message, data) => {
		const line = data?.ruleName ? `${message} (${data.ruleName})` : message;
		if (warned.has(line)) return;
		warned.add(line);
		notify(`TTSR: ${line}`, "warning");
	};

	function readSettings(): TtsrSettings {
		const file = path.join(getAgentDir(), "ttsr.json");
		if (!existsSync(file)) return { ...DEFAULT_SETTINGS };
		try {
			return { ...DEFAULT_SETTINGS, ...(JSON.parse(readFileSync(file, "utf8")) as Partial<TtsrSettings>) };
		} catch (error) {
			log.warn(`ttsr.json is invalid: ${error instanceof Error ? error.message : String(error)}`);
			return { ...DEFAULT_SETTINGS };
		}
	}

	function ruleDirs(ctx: ExtensionContext): { dir: string; level: RuleLevel }[] {
		const dirs: { dir: string; level: RuleLevel }[] = [];
		// Untrusted repos must not inject rule text.
		if (ctx.isProjectTrusted()) dirs.push({ dir: path.join(ctx.cwd, ".pi", "rules"), level: "project" });
		// Unbuilt checkout edits win over deployed copies.
		if (settings.rulesSource) dirs.push({ dir: settings.rulesSource, level: "user" });
		dirs.push({ dir: path.join(getAgentDir(), "rules"), level: "user" });
		return dirs;
	}

	function loadRules(ctx: ExtensionContext): Rule[] {
		const rules = new Map<string, Rule>();
		for (const { dir, level } of ruleDirs(ctx)) {
			if (!existsSync(dir)) continue;
			for (const file of readdirSync(dir).sort()) {
				if (!/\.(md|mdc)$/.test(file)) continue;
				const filePath = path.join(dir, file);
				try {
					const { frontmatter, body } = parseFrontmatter<RuleFrontmatter>(readFileSync(filePath, "utf8"));
					if (frontmatter.enabled === false) continue;
					const rule = buildRule(file, body, frontmatter, filePath, level);
					if (!rules.has(rule.name) && !settings.disabledRules.includes(rule.name)) rules.set(rule.name, rule);
				} catch (error) {
					log.warn(`cannot read rule ${filePath}: ${error instanceof Error ? error.message : String(error)}`);
				}
			}
		}
		return Array.from(rules.values());
	}

	function persist(entry: StateEntry): void {
		pi.appendEntry<StateEntry>(STATE_TYPE, entry);
	}

	function interrupts(rule: Rule, source: Source): boolean {
		const mode = rule.interruptMode ?? settings.interruptMode;
		if (mode === "always") return true;
		if (mode === "prose-only") return source !== "tool";
		if (mode === "tool-only") return source === "tool";
		return false;
	}

	function renderRules(template: string, rules: readonly Rule[], subject?: string): string {
		return rules
			.map(rule => render(template, { name: rule.name, path: rule.path, content: rule.content.trim(), subject }))
			.join("\n\n");
	}

	function drafts(content: string, rules: readonly Rule[]): SessionBoundaryDraft[] {
		const names = rules.map(rule => rule.name);
		return [
			{ type: "custom", customType: STATE_TYPE, data: { injected: names } satisfies StateEntry },
			{ type: "custom_message", customType: MESSAGE_TYPE, content, display: true, details: { rules: names } },
		];
	}

	// Outside a boundary: verdicts landing after settle.
	function inject(content: string, rules: readonly Rule[], options: Parameters<ExtensionAPI["sendMessage"]>[1]): void {
		const names = rules.map(rule => rule.name);
		persist({ injected: names });
		void pi.sendMessage({ customType: MESSAGE_TYPE, content, display: true, details: { rules: names } }, options);
	}

	async function resolveJudge(ctx: ExtensionContext): Promise<Judge | undefined> {
		if (settings.judge === "off") return undefined;
		const registry = ctx.modelRegistry;
		let model = ctx.model;
		if (settings.judgeModel) {
			const slash = settings.judgeModel.indexOf("/");
			const provider = settings.judgeModel.slice(0, slash);
			const id = settings.judgeModel.slice(slash + 1);
			const classifier = registry.getModelOfType("classifier", provider, id);
			if (classifier) {
				return classifierJudge(settings.judgeModel, (context, signal) =>
					registry.classify(classifier, context, { signal }),
				);
			}
			model = registry.find(provider, id) ?? model;
		}
		if (!model) return undefined;
		const level = ctx.thinkingLevel;
		const chosen = model;
		return chatJudge(`${chosen.provider}/${chosen.id}`, async (prompt, signal) => {
			const stream = registry.streamSimple(
				chosen,
				{ messages: [{ role: "user", content: prompt, timestamp: Date.now() }] },
				{ signal, reasoning: level && level !== "off" ? level : undefined },
			);
			const reply = await stream.result();
			if (reply.stopReason === "error" || reply.stopReason === "aborted") {
				throw new Error(reply.errorMessage ?? `judge ${reply.stopReason}`);
			}
			return reply.content.map(block => (block.type === "text" ? block.text : "")).join("");
		});
	}

	async function judgeMessage(message: unknown, ctx: ExtensionContext): Promise<void> {
		if (!isAssistantMessage(message)) return;
		const started = generation;
		let judge: Judge | undefined;
		for (const output of inspector.outputs(message)) {
			const candidates = await manager.judgedCandidates(output.content, output.context);
			if (candidates.length === 0) continue;
			judge ??= await resolveJudge(ctx);
			if (!judge) return;
			let flagged: Rule[];
			try {
				flagged = await judgeRules(judge, output, candidates);
			} catch (error) {
				log.warn(`judge failed: ${error instanceof Error ? error.message : String(error)}`);
				continue;
			}
			if (started !== generation) return;
			const claimed = manager.claim(flagged);
			if (claimed.length === 0) continue;
			const content = renderRules("ttsr-warning", claimed, output.subject);
			if (settleWarnings) settleWarnings.push(...drafts(content, claimed));
			else inject(content, claimed, ctx.isIdle() ? { triggerTurn: true } : { deliverAs: "steer" });
		}
	}

	pi.on("session_start", (_event, ctx) => {
		generation++;
		notify = (message, type) => ctx.ui.notify(message, type);
		warned.clear();
		settings = readSettings();
		manager = new TtsrManager(() => settings, astMatch);
		inspector = new TtsrToolInspector(() => ctx.cwd);
		pendingInterrupt = undefined;
		pendingRetry = undefined;
		deferredProse.clear();
		toolReminders.clear();
		turnReminders.length = 0;
		settleWarnings = undefined;
		if (!settings.enabled) return;
		for (const rule of loadRules(ctx)) manager.addRule(rule);
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "custom" || entry.customType !== STATE_TYPE) continue;
			const data = entry.data as StateEntry | undefined;
			if (data?.injected) manager.restoreInjected(data.injected);
		}
	});

	pi.on("turn_start", () => manager.resetBuffer());

	pi.on("message_start", event => {
		if (isAssistantMessage(event.message)) manager.resetBuffer();
	});

	pi.on("message_update", (event, ctx) => {
		if (pendingInterrupt || !manager.hasRules()) return;
		const update = event.assistantMessageEvent;
		let source: Source;
		if (update.type === "text_delta") source = "text";
		else if (update.type === "thinking_delta") source = "thinking";
		else return;
		const matches = manager.checkDelta(update.delta, { source });
		if (matches.length === 0) return;
		const interrupting = matches.filter(rule => interrupts(rule, source));
		for (const rule of matches) if (!interrupts(rule, source)) deferredProse.set(rule.name, rule);
		if (interrupting.length === 0) return;
		manager.markInjected(interrupting);
		pendingInterrupt = interrupting;
		ctx.ui.notify(`TTSR: injecting rule ${interrupting.map(rule => rule.name).join(", ")}`, "warning");
		ctx.abort();
	});

	pi.on("message_end", (event, ctx) => {
		const message = event.message as { stopReason?: string };
		if (!isAssistantMessage(message) || pendingInterrupt) return;
		if (message.stopReason === "aborted" || message.stopReason === "error") return;
		if (!manager.hasJudgedRules()) return;
		const judgment = judgeMessage(message, ctx).finally(() => pendingJudgments.delete(judgment));
		pendingJudgments.add(judgment);
	});

	pi.on("turn_end", event => {
		manager.incrementMessageCount();
		const entries: SessionBoundaryDraft[] = [];
		const message = event.message as { stopReason?: string };
		if (pendingInterrupt) {
			const rules = pendingInterrupt;
			pendingInterrupt = undefined;
			deferredProse.clear();
			turnReminders.length = 0;
			pendingRetry = rules;
			// Omit the cut-off attempt from model context.
			if (settings.contextMode === "discard") {
				entries.push({ type: "context_edit", targetId: event.messageEntryId, replacement: null });
			}
			return { entries };
		}
		if (message.stopReason === "aborted" || message.stopReason === "error") {
			deferredProse.clear();
			toolReminders.clear();
			turnReminders.length = 0;
			return;
		}
		if (turnReminders.length > 0) {
			const rules = turnReminders.splice(0);
			entries.push(...drafts(renderRules("ttsr-tool-reminder", rules), rules));
		}
		if (deferredProse.size > 0) {
			const rules = manager.claim(Array.from(deferredProse.values()));
			deferredProse.clear();
			if (rules.length > 0) entries.push(...drafts(renderRules("ttsr-interrupt", rules), rules));
		}
		if (entries.length === 0) return;
		return { entries, continue: true };
	});

	// Aborted runs cannot continue; pi defers this.
	pi.on("agent_settled", () => {
		const rules = pendingRetry;
		if (!rules) return;
		pendingRetry = undefined;
		inject(renderRules("ttsr-interrupt", rules), rules, { triggerTurn: true });
	});

	pi.on("agent_before_settle", async () => {
		if (pendingJudgments.size === 0) return;
		settleWarnings = [];
		let timer: ReturnType<typeof setTimeout> | undefined;
		await Promise.race([
			Promise.allSettled(Array.from(pendingJudgments)),
			new Promise(resolve => {
				timer = setTimeout(resolve, JUDGE_WAIT_MS);
			}),
		]);
		clearTimeout(timer);
		const entries = settleWarnings;
		settleWarnings = undefined;
		if (entries.length === 0) return;
		return { entries, continue: true };
	});

	pi.on("tool_call", async event => {
		if (!manager.hasRules()) return;
		const call = { id: event.toolCallId, name: event.toolName, arguments: event.input };
		const output = inspector.toolCallOutput(call, 0);
		const matches = manager.checkSnapshot(output.content, output.context);
		const digest = inspector.digest(call);
		if (digest !== undefined && manager.hasAstRules()) {
			for (const rule of await manager.checkAstSnapshot(digest, output.context)) {
				if (!matches.includes(rule)) matches.push(rule);
			}
		}
		if (matches.length === 0) return;
		const passive = matches.filter(rule => !interrupts(rule, "tool"));
		const interrupting = matches.filter(rule => interrupts(rule, "tool"));
		if (passive.length > 0) {
			manager.markInjected(passive);
			toolReminders.set(event.toolCallId, passive);
		}
		if (interrupting.length === 0) return;
		manager.markInjected(interrupting);
		persist({ injected: interrupting.map(rule => rule.name) });
		notify(`TTSR: blocked ${output.subject} by ${interrupting.map(rule => rule.name).join(", ")}`, "warning");
		return { block: true, reason: renderRules("ttsr-interrupt", interrupting) };
	});

	pi.on("tool_result", event => {
		const rules = toolReminders.get(event.toolCallId);
		if (!rules) return;
		toolReminders.delete(event.toolCallId);
		turnReminders.push(...rules);
	});

	pi.on("session_shutdown", () => {
		generation++;
	});

	pi.registerCommand("ttsr", {
		description: "List loaded TTSR rules",
		handler: async (_args, ctx) => {
			const injected = new Set(manager.getInjectedRuleNames());
			const rules = manager.getRules();
			if (rules.length === 0) {
				ctx.ui.notify("TTSR: no rules loaded.", "info");
				return;
			}
			const lines = rules.map(rule => {
				const triggers = [
					rule.condition && `condition ${JSON.stringify(rule.condition)}`,
					rule.astCondition && `astCondition ${JSON.stringify(rule.astCondition)}`,
					rule.question && `question ${JSON.stringify(rule.question)}`,
				].filter(Boolean);
				const state = injected.has(rule.name) ? " [injected]" : "";
				return `${rule.name} (${rule.level})${state}: ${triggers.join(" / ")} scope ${JSON.stringify(rule.scope ?? "default")}`;
			});
			ctx.ui.notify(lines.join("\n"), "info");
		},
	});

	pi.registerCommand("omfg", {
		description: "Forge a TTSR rule from a complaint",
		handler: async (args, ctx) => {
			await runOmfg(args.trim(), ctx);
		},
	});

	pi.registerEntryRenderer<DraftEntry>(DRAFT_TYPE, (entry, _options, theme) => {
		if (!entry.data) return undefined;
		const box = new Box(1, 1, text => theme.bg("customMessageBg", text));
		box.addChild(new Text(theme.fg("accent", `[omfg] ${entry.data.status}`), 0, 0));
		box.addChild(new Text(entry.data.content, 0, 0));
		return box;
	});

	function transcript(messages: readonly unknown[]): string {
		const parts: string[] = [];
		for (const raw of messages) {
			const message = raw as { role?: string; content?: unknown; toolName?: string; customType?: string };
			const blocks = typeof message.content === "string" ? [{ type: "text", text: message.content }] : message.content;
			if (!Array.isArray(blocks)) continue;
			for (const block of blocks as { type: string; text?: string; name?: string; arguments?: unknown }[]) {
				if (block.type === "text" && block.text) {
					const label = message.role === "toolResult" ? `TOOL RESULT (${message.toolName ?? "?"})` : (message.role ?? "?").toUpperCase();
					const text = message.role === "toolResult" ? block.text.slice(0, 4000) : block.text;
					parts.push(`[${label}]\n${text}`);
				} else if (block.type === "toolCall") {
					parts.push(`[TOOL CALL ${block.name}]\n${JSON.stringify(block.arguments ?? {})}`);
				}
			}
		}
		const text = parts.join("\n\n");
		return text.length <= MAX_TRANSCRIPT_CHARS ? text : text.slice(text.length - MAX_TRANSCRIPT_CHARS);
	}

	async function generateRule(
		ctx: ExtensionCommandContext,
		complaint: string,
		conversation: string,
		feedback: string | undefined,
		previousRule: string | undefined,
		show: (status: string, draft?: string) => void,
	): Promise<string> {
		const model = ctx.model;
		if (!model) throw new Error("No active model available for /omfg.");
		const prompt = `<conversation>\n${conversation}\n</conversation>\n\n${render("omfg-user", { complaint, feedback, previousRule })}`;
		const level = ctx.thinkingLevel;
		const stream = ctx.modelRegistry.streamSimple(
			model,
			{
				systemPrompt: "You author Time Traveling Stream Rules that stop a coding agent's recurring mistakes.",
				messages: [{ role: "user", content: prompt, timestamp: Date.now() }],
			},
			{ reasoning: level && level !== "off" ? level : undefined },
		);
		let draft = "";
		let lastShown = 0;
		for await (const update of stream) {
			if (update.type !== "text_delta") continue;
			draft += update.delta;
			if (Date.now() - lastShown > 250) {
				lastShown = Date.now();
				show("generating...", draft);
			}
		}
		const reply = await stream.result();
		if (reply.stopReason === "error" || reply.stopReason === "aborted") {
			throw new Error(reply.errorMessage ?? `model ${reply.stopReason}`);
		}
		return reply.content.map(block => (block.type === "text" ? block.text : "")).join("");
	}

	async function runOmfg(complaint: string, ctx: ExtensionCommandContext): Promise<void> {
		if (!complaint) {
			ctx.ui.notify("Usage: /omfg <complaint>", "warning");
			return;
		}
		if (!ctx.model) {
			ctx.ui.notify("No active model available for /omfg.", "error");
			return;
		}
		const show = (status: string, rule?: string) =>
			ctx.ui.setWidget("omfg", [`/omfg ${complaint}`, status, ...(rule ? rule.split("\n") : [])]);
		try {
			const messages = buildSessionContext(ctx.sessionManager.getEntries(), ctx.sessionManager.getLeafId()).messages;
			const conversation = transcript(messages);
			const outputs = historyOutputs(messages, inspector);
			let feedback: string[] = [];
			let previousRule: string | undefined;
			for (;;) {
				let candidate: (ParsedGeneratedRule & { validated: boolean }) | undefined;
				let last: ParsedGeneratedRule | undefined;
				for (let attempt = 1; attempt <= MAX_ATTEMPTS && !candidate; attempt++) {
					show(`Attempt ${attempt}/${MAX_ATTEMPTS}: generating...`);
					const reply = await generateRule(
						ctx,
						complaint,
						conversation,
						feedback.length > 0 ? feedback.join("\n\n") : undefined,
						previousRule,
						(status, draft) => show(`Attempt ${attempt}/${MAX_ATTEMPTS}: ${status}`, draft),
					);
					const parsed = parseGeneratedRule(reply);
					if ("error" in parsed) {
						const failed = extractGeneratedRuleJson(reply) ?? reply.trim();
						feedback.push(`Attempt ${attempt} failed: invalid rule (${parsed.error}).\nFailed candidate:\n${failed}`);
						previousRule = failed;
						show(`Attempt ${attempt}/${MAX_ATTEMPTS}: ${parsed.error}`);
						continue;
					}
					show(`Attempt ${attempt}/${MAX_ATTEMPTS}: validating...`, parsed.fileContent);
					const judge = parsed.rule.question !== undefined ? await resolveJudge(ctx) : undefined;
					const validated = await validateParsedRuleAgainstAssistantHistory(parsed, outputs, judge, astMatch);
					if (validated.validation.matched) {
						candidate = { ...validated.candidate, validated: true };
					} else if (validated.validation.judgeUnavailable) {
						candidate = { ...validated.candidate, validated: false };
					} else {
						last = validated.candidate;
						const failure = validated.validation.feedback ?? "The rule did not match any earlier assistant output.";
						feedback.push(
							`Attempt ${attempt} failed validation:\n${failure}\nFailed candidate:\n${validated.candidate.fileContent}`,
						);
						previousRule = validated.candidate.fileContent;
					}
				}
				candidate ??= last ? { ...last, validated: false } : undefined;
				if (!candidate) {
					ctx.ui.notify("The model did not return a valid TTSR rule.", "error");
					return;
				}
				const status = candidate.validated
					? "Validated against this conversation."
					: "Not confirmed against this conversation.";
				// A displaced dialog would strand the widget.
				ctx.ui.setWidget("omfg", undefined);
				pi.appendEntry<DraftEntry>(DRAFT_TYPE, { status, content: candidate.fileContent });
				if (
					!candidate.validated &&
					!(await ctx.ui.confirm("Validation", "Couldn't confirm this rule matches the conversation. Save anyway?"))
				) {
					return;
				}
				const globalDir = settings.rulesSource ?? path.join(getAgentDir(), "rules");
				const globalOption = `Global, all projects (${globalDir.replace(os.homedir(), "~")})`;
				const choice = await ctx.ui.select("Save TTSR rule where?", [PROJECT_OPTION, globalOption, AMEND_OPTION]);
				if (!choice) return;
				if (choice === AMEND_OPTION) {
					const amendment = (await ctx.ui.input("Amend TTSR rule", "e.g. only match tool:write(*.rb)"))?.trim();
					if (!amendment) continue;
					feedback = [`User requested this amendment before saving:\n${amendment}`];
					previousRule = candidate.fileContent;
					continue;
				}
				const level: RuleLevel = choice === globalOption ? "user" : "project";
				const dir = level === "user" ? globalDir : path.join(ctx.cwd, ".pi", "rules");
				const filePath = path.join(dir, `${candidate.rule.name}.md`);
				if (existsSync(filePath) && !(await ctx.ui.confirm("Overwrite TTSR rule?", `${filePath} exists. Overwrite it?`))) {
					return;
				}
				mkdirSync(dir, { recursive: true });
				writeFileSync(filePath, candidate.fileContent);
				manager.removeRule(candidate.rule.name);
				manager.addRule(withPath(candidate.rule, filePath, level));
				ctx.ui.notify(`Saved TTSR rule ${candidate.rule.name} to ${filePath}`, "info");
				if (level === "user" && settings.rulesSource) {
					ctx.ui.notify("Commit the rule, then rebuild to deploy it.", "info");
				}
				if (level === "project" && !ctx.isProjectTrusted()) {
					ctx.ui.notify("Project not trusted: rule loads only once trusted.", "warning");
				}
				return;
			}
		} catch (error) {
			ctx.ui.notify(`/omfg failed: ${error instanceof Error ? error.message : String(error)}`, "error");
		} finally {
			ctx.ui.setWidget("omfg", undefined);
		}
	}
}
