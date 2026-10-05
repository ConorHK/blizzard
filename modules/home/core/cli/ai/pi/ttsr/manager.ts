// Ported from oh-my-pi (MIT): export/ttsr.ts, export/ttsr-settings.ts.
import * as path from "node:path";
import picomatch from "picomatch";
import { compileRuleCondition, type Rule } from "./rule.ts";

export type TtsrMatchSource = "text" | "thinking" | "tool";

export interface TtsrMatchContext {
	source: TtsrMatchSource;
	toolName?: string;
	filePaths?: string[];
	streamKey?: string;
}

export interface TtsrOutput {
	content: string;
	context: TtsrMatchContext;
	subject: string;
}

export interface JudgedCandidate {
	rule: Rule;
	question: string;
}

export interface TtsrSettings {
	enabled: boolean;
	judge: "auto" | "off";
	judgeModel?: string;
	contextMode: "discard" | "keep";
	interruptMode: "always" | "prose-only" | "tool-only" | "never";
	repeatMode: "once" | "after-gap";
	repeatGap: number;
	disabledRules: string[];
	/** Checkout dir /omfg saves global rules to. */
	rulesSource?: string;
}

export const DEFAULT_SETTINGS: TtsrSettings = {
	enabled: true,
	judge: "auto",
	contextMode: "discard",
	interruptMode: "always",
	repeatMode: "once",
	repeatGap: 10,
	disabledRules: [],
};

export type AstMatcher = (patterns: string[], source: string, lang: string) => Promise<boolean>;

export const log = {
	warn: (_message: string, _data?: Record<string, unknown>): void => {},
};

type Glob = (input: string) => boolean;

function compileGlob(pattern: string): Glob {
	return picomatch(pattern, { dot: true });
}

interface ToolScope {
	toolName?: string;
	pathGlob?: Glob;
	pathPattern?: string;
}

interface TtsrScope {
	allowText: boolean;
	allowThinking: boolean;
	allowAnyTool: boolean;
	toolScopes: ToolScope[];
}

interface TtsrEntry {
	rule: Rule;
	conditions: RegExp[];
	astConditions: string[];
	question?: string;
	scope: TtsrScope;
	globalPathGlobs?: Glob[];
}

interface InjectionRecord {
	lastInjectedAt: number;
}

const DEFAULT_SCOPE: TtsrScope = {
	allowText: true,
	allowThinking: false,
	allowAnyTool: true,
	toolScopes: [],
};

const noAst: AstMatcher = async () => false;

export class TtsrManager {
	readonly #settingsSource: () => TtsrSettings;
	readonly #astMatch: AstMatcher;
	readonly #rules = new Map<string, TtsrEntry>();
	readonly #injectionRecords = new Map<string, InjectionRecord>();
	readonly #buffers = new Map<string, string>();
	readonly #lastAstSnapshots = new Map<string, string>();
	#messageCount = 0;
	#canMatchText = false;
	#canMatchThinking = false;
	#hasJudgedRules = false;

	constructor(settings?: Partial<TtsrSettings> | (() => TtsrSettings), astMatch: AstMatcher = noAst) {
		if (typeof settings === "function") {
			this.#settingsSource = settings;
		} else {
			const snapshot: TtsrSettings = { ...DEFAULT_SETTINGS, ...settings };
			this.#settingsSource = () => snapshot;
		}
		this.#astMatch = astMatch;
	}

	get #settings(): TtsrSettings {
		return this.#settingsSource();
	}

	#canTrigger(ruleName: string): boolean {
		const record = this.#injectionRecords.get(ruleName);
		if (!record) return true;
		if (this.#settings.repeatMode === "once") return false;
		return this.#messageCount - record.lastInjectedAt >= this.#settings.repeatGap;
	}

	#compileConditions(rule: Rule): RegExp[] {
		const compiled: RegExp[] = [];
		for (const pattern of rule.condition ?? []) {
			try {
				compiled.push(compileRuleCondition(pattern));
			} catch (error) {
				log.warn("TTSR condition has invalid regex pattern, skipping condition", {
					ruleName: rule.name,
					pattern,
					error: error instanceof Error ? error.message : String(error),
				});
			}
		}
		return compiled;
	}

	#compileGlobalPathGlobs(globs: Rule["globs"]): Glob[] | undefined {
		if (!globs || globs.length === 0) return undefined;
		const compiled = globs
			.map(glob => glob.trim())
			.filter(glob => glob.length > 0)
			.map(compileGlob);
		return compiled.length > 0 ? compiled : undefined;
	}

	#parseToolScopeToken(token: string): ToolScope | undefined {
		const match = /^(?:(?<prefix>tool)(?::(?<tool>[a-z0-9_-]+))?|(?<bare>[a-z0-9_-]+))(?:\((?<path>[^)]+)\))?$/i.exec(
			token,
		);
		if (!match) return undefined;
		const groups = match.groups;
		const hasToolPrefix = groups?.prefix !== undefined;
		const toolName = (groups?.tool ?? (hasToolPrefix ? undefined : groups?.bare))?.trim().toLowerCase();
		const pathPattern = groups?.path?.trim();
		if (!pathPattern) return { toolName };
		return { toolName, pathPattern, pathGlob: compileGlob(pathPattern) };
	}

	#buildScope(rule: Rule): TtsrScope {
		if (!rule.scope || rule.scope.length === 0) {
			return { ...DEFAULT_SCOPE, toolScopes: [...DEFAULT_SCOPE.toolScopes] };
		}
		const scope: TtsrScope = { allowText: false, allowThinking: false, allowAnyTool: false, toolScopes: [] };
		for (const rawToken of rule.scope) {
			const token = rawToken.trim();
			const normalizedToken = token.toLowerCase();
			if (token.length === 0) continue;
			if (normalizedToken === "text") {
				scope.allowText = true;
				continue;
			}
			if (normalizedToken === "thinking") {
				scope.allowThinking = true;
				continue;
			}
			if (normalizedToken === "tool" || normalizedToken === "toolcall") {
				scope.allowAnyTool = true;
				continue;
			}
			const toolScope = this.#parseToolScopeToken(token);
			if (!toolScope) {
				log.warn("TTSR scope token is invalid, skipping token", { ruleName: rule.name, token: rawToken });
				continue;
			}
			if (!toolScope.toolName && !toolScope.pathGlob) {
				scope.allowAnyTool = true;
				continue;
			}
			scope.toolScopes.push(toolScope);
		}
		return scope;
	}

	#hasReachableScope(scope: TtsrScope): boolean {
		return scope.allowText || scope.allowThinking || scope.allowAnyTool || scope.toolScopes.length > 0;
	}

	#bufferKey(context: TtsrMatchContext): string {
		if (context.streamKey && context.streamKey.trim().length > 0) return context.streamKey;
		if (context.source !== "tool") return context.source;
		const toolName = context.toolName?.trim().toLowerCase();
		return toolName ? `tool:${toolName}` : "tool";
	}

	#normalizePath(pathValue: string): string {
		return pathValue.replaceAll("\\", "/");
	}

	#matchesGlob(glob: Glob, filePaths: string[] | undefined): boolean {
		if (!filePaths || filePaths.length === 0) return false;
		for (const filePath of filePaths) {
			const normalized = this.#normalizePath(filePath);
			if (glob(normalized)) return true;
			const slashIndex = normalized.lastIndexOf("/");
			const basename = slashIndex === -1 ? normalized : normalized.slice(slashIndex + 1);
			if (basename !== normalized && glob(basename)) return true;
		}
		return false;
	}

	#matchesGlobalPaths(entry: TtsrEntry, context: TtsrMatchContext): boolean {
		if (!entry.globalPathGlobs || entry.globalPathGlobs.length === 0) return true;
		return entry.globalPathGlobs.some(glob => this.#matchesGlob(glob, context.filePaths));
	}

	#matchesScope(entry: TtsrEntry, context: TtsrMatchContext): boolean {
		if (context.source === "text") return entry.scope.allowText;
		if (context.source === "thinking") return entry.scope.allowThinking;
		if (entry.scope.allowAnyTool) return true;
		const toolName = context.toolName?.trim().toLowerCase();
		for (const toolScope of entry.scope.toolScopes) {
			if (toolScope.toolName && toolScope.toolName !== toolName) continue;
			if (toolScope.pathGlob && !this.#matchesGlob(toolScope.pathGlob, context.filePaths)) continue;
			return true;
		}
		return false;
	}

	#matchesCondition(entry: TtsrEntry, streamBuffer: string): boolean {
		for (const condition of entry.conditions) {
			condition.lastIndex = 0;
			if (condition.test(streamBuffer)) return true;
		}
		return false;
	}

	addRule(rule: Rule): boolean {
		if (!this.#settings.enabled) return false;
		if (this.#rules.has(rule.name)) return false;
		const conditions = this.#compileConditions(rule);
		const astConditions = (rule.astCondition ?? []).map(pattern => pattern.trim()).filter(p => p.length > 0);
		const question = rule.question?.trim() || undefined;
		if (conditions.length === 0 && astConditions.length === 0 && !question) return false;
		const scope = this.#buildScope(rule);
		if (!this.#hasReachableScope(scope)) {
			log.warn("TTSR scope excludes all streams, skipping rule", { ruleName: rule.name, scope: rule.scope });
			return false;
		}
		const globalPathGlobs = this.#compileGlobalPathGlobs(rule.globs);
		this.#rules.set(rule.name, { rule, conditions, astConditions, question, scope, globalPathGlobs });
		if (question) {
			this.#hasJudgedRules = true;
		} else {
			if (scope.allowText) this.#canMatchText = true;
			if (scope.allowThinking) this.#canMatchThinking = true;
		}
		return true;
	}

	/** Buffer a stream chunk, then match. */
	checkDelta(delta: string, context: TtsrMatchContext): Rule[] {
		if (context.source === "text" && !this.#canMatchText) return [];
		if (context.source === "thinking" && !this.#canMatchThinking) return [];
		const bufferKey = this.#bufferKey(context);
		const nextBuffer = `${this.#buffers.get(bufferKey) ?? ""}${delta}`;
		this.#buffers.set(bufferKey, nextBuffer);
		return this.#matchBuffer(nextBuffer, context);
	}

	/** Match a full snapshot, replacing the buffer. */
	checkSnapshot(snapshot: string, context: TtsrMatchContext): Rule[] {
		this.#buffers.set(this.#bufferKey(context), snapshot);
		return this.#matchBuffer(snapshot, context);
	}

	#deriveLang(filePaths: string[] | undefined): string | undefined {
		for (const filePath of filePaths ?? []) {
			const ext = path.extname(this.#normalizePath(filePath));
			if (ext.length > 1) return ext.slice(1).toLowerCase();
		}
		return undefined;
	}

	async checkAstSnapshot(snapshot: string, context: TtsrMatchContext): Promise<Rule[]> {
		if (!this.#settings.enabled || context.source !== "tool") return [];
		const lang = this.#deriveLang(context.filePaths);
		if (!lang) return [];
		const candidates: TtsrEntry[] = [];
		for (const [name, entry] of this.#rules) {
			if (entry.astConditions.length === 0 || entry.question) continue;
			if (!this.#canTrigger(name) || !this.#matchesScope(entry, context) || !this.#matchesGlobalPaths(entry, context)) {
				continue;
			}
			candidates.push(entry);
		}
		if (candidates.length === 0) return [];
		const bufferKey = this.#bufferKey(context);
		if (this.#lastAstSnapshots.get(bufferKey) === snapshot) return [];
		this.#lastAstSnapshots.set(bufferKey, snapshot);
		const matches: Rule[] = [];
		for (const entry of candidates) {
			if (await this.#astConditionsMatch(entry.astConditions, snapshot, lang)) matches.push(entry.rule);
		}
		return matches;
	}

	async #astConditionsMatch(patterns: string[], source: string, lang: string): Promise<boolean> {
		try {
			return await this.#astMatch(patterns, source, lang);
		} catch (error) {
			log.warn("TTSR ast match failed, treating as no match", {
				patterns,
				lang,
				error: error instanceof Error ? error.message : String(error),
			});
			return false;
		}
	}

	hasAstRules(): boolean {
		if (!this.#settings.enabled) return false;
		for (const entry of this.#rules.values()) {
			if (entry.astConditions.length > 0 && !entry.question) return true;
		}
		return false;
	}

	hasJudgedRules(): boolean {
		return this.#settings.enabled && this.#hasJudgedRules;
	}

	async judgedCandidates(content: string, context: TtsrMatchContext): Promise<JudgedCandidate[]> {
		if (!this.hasJudgedRules()) return [];
		const candidates: JudgedCandidate[] = [];
		for (const [name, entry] of this.#rules) {
			if (
				!entry.question ||
				!this.#canTrigger(name) ||
				!this.#matchesScope(entry, context) ||
				!this.#matchesGlobalPaths(entry, context) ||
				!(await this.#passesPrefilter(entry, content, context))
			) {
				continue;
			}
			candidates.push({ rule: entry.rule, question: entry.question });
		}
		return candidates;
	}

	async #passesPrefilter(entry: TtsrEntry, content: string, context: TtsrMatchContext): Promise<boolean> {
		if (entry.conditions.length === 0 && entry.astConditions.length === 0) return true;
		if (this.#matchesCondition(entry, content)) return true;
		const lang = context.source === "tool" ? this.#deriveLang(context.filePaths) : undefined;
		return lang !== undefined && entry.astConditions.length > 0
			? this.#astConditionsMatch(entry.astConditions, content, lang)
			: false;
	}

	/** Marks repeatable rules injected, drops others. */
	claim(rules: readonly Rule[]): Rule[] {
		const claimed = rules.filter(rule => this.#canTrigger(rule.name));
		this.markInjected(claimed);
		return claimed;
	}

	#matchBuffer(buffer: string, context: TtsrMatchContext): Rule[] {
		if (!this.#settings.enabled) return [];
		const matches: Rule[] = [];
		for (const [name, entry] of this.#rules) {
			if (entry.question || !this.#canTrigger(name)) continue;
			if (!this.#matchesScope(entry, context)) continue;
			if (!this.#matchesGlobalPaths(entry, context)) continue;
			if (!this.#matchesCondition(entry, buffer)) continue;
			matches.push(entry.rule);
		}
		return matches;
	}

	markInjected(rulesToMark: readonly Rule[]): void {
		this.markInjectedByNames(rulesToMark.map(rule => rule.name));
	}

	markInjectedByNames(ruleNames: readonly string[]): void {
		for (const rawName of ruleNames) {
			const ruleName = rawName.trim();
			if (ruleName.length === 0) continue;
			const record = this.#injectionRecords.get(ruleName);
			if (!record) this.#injectionRecords.set(ruleName, { lastInjectedAt: this.#messageCount });
			else record.lastInjectedAt = this.#messageCount;
		}
	}

	getInjectedRuleNames(): string[] {
		return Array.from(this.#injectionRecords.keys());
	}

	restoreInjected(ruleNames: readonly string[]): void {
		for (const name of ruleNames) this.#injectionRecords.set(name, { lastInjectedAt: 0 });
	}

	resetBuffer(): void {
		this.#buffers.clear();
		this.#lastAstSnapshots.clear();
	}

	hasRules(): boolean {
		return this.#settings.enabled && this.#rules.size > 0;
	}

	removeRule(name: string): void {
		if (!this.#rules.delete(name)) return;
		this.#canMatchText = false;
		this.#canMatchThinking = false;
		this.#hasJudgedRules = false;
		for (const entry of this.#rules.values()) {
			if (entry.question) this.#hasJudgedRules = true;
			else {
				if (entry.scope.allowText) this.#canMatchText = true;
				if (entry.scope.allowThinking) this.#canMatchThinking = true;
			}
		}
	}

	getRules(): Rule[] {
		return Array.from(this.#rules.values(), entry => entry.rule);
	}

	incrementMessageCount(): void {
		this.#messageCount++;
	}

	getSettings(): TtsrSettings {
		return this.#settings;
	}
}
