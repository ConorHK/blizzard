// Ported from oh-my-pi (MIT): capability/rule.ts, discovery/helpers.ts.

export type RuleLevel = "user" | "project";
export type InterruptMode = "never" | "prose-only" | "tool-only" | "always";

export interface RuleFrontmatter {
	enabled?: boolean;
	description?: string;
	globs?: string[] | string;
	condition?: string | string[];
	astCondition?: string | string[];
	question?: string;
	scope?: string | string[];
	interruptMode?: InterruptMode;
	[key: string]: unknown;
}

export interface Rule {
	name: string;
	path: string;
	content: string;
	level: RuleLevel;
	globs?: string[];
	description?: string;
	condition?: string[];
	astCondition?: string[];
	question?: string;
	scope?: string[];
	interruptMode?: InterruptMode;
}

const CONDITION_GLOB_SCOPE_TOOLS = ["edit", "write"] as const;

function normalizeRuleField(value: unknown): string[] | undefined {
	if (typeof value === "string") {
		const token = value.trim();
		return token.length > 0 ? [token] : undefined;
	}
	if (!Array.isArray(value)) return undefined;
	const tokens = value
		.filter((item): item is string => typeof item === "string")
		.map(item => item.trim())
		.filter(item => item.length > 0);
	return tokens.length > 0 ? Array.from(new Set(tokens)) : undefined;
}

function splitScopeTokens(value: string): string[] {
	const tokens: string[] = [];
	let current = "";
	let parenDepth = 0;
	let bracketDepth = 0;
	let braceDepth = 0;
	let quote: '"' | "'" | undefined;
	for (let i = 0; i < value.length; i++) {
		const char = value[i];
		if (quote) {
			current += char;
			if (char === quote && value[i - 1] !== "\\") quote = undefined;
			continue;
		}
		if (char === '"' || char === "'") {
			quote = char;
			current += char;
			continue;
		}
		if (char === "(") parenDepth++;
		else if (char === ")") parenDepth = Math.max(0, parenDepth - 1);
		else if (char === "[") bracketDepth++;
		else if (char === "]") bracketDepth = Math.max(0, bracketDepth - 1);
		else if (char === "{") braceDepth++;
		else if (char === "}") braceDepth = Math.max(0, braceDepth - 1);
		else if (char === "," && parenDepth === 0 && bracketDepth === 0 && braceDepth === 0) {
			const token = current.trim();
			if (token.length > 0) tokens.push(token);
			current = "";
			continue;
		}
		current += char;
	}
	const tail = current.trim();
	if (tail.length > 0) tokens.push(tail);
	return tokens;
}

function normalizeScopeField(value: unknown): string[] | undefined {
	const normalized = normalizeRuleField(value);
	if (!normalized) return undefined;
	const tokens = normalized
		.flatMap(splitScopeTokens)
		.map(token => {
			const quote = token[0];
			if (token.length >= 2 && (quote === '"' || quote === "'") && token[token.length - 1] === quote) {
				return token.slice(1, -1).trim();
			}
			return token;
		})
		.filter(item => item.length > 0);
	return tokens.length > 0 ? Array.from(new Set(tokens)) : undefined;
}

// `*.rs` as a condition means file scope.
function isLikelyFileGlob(value: string): boolean {
	const token = value.trim();
	if (token.length === 0) return false;
	if (/[\\^$+|()]/.test(token)) return false;
	if (!/[?*[\]{}]/.test(token)) return false;
	if (token.includes("/")) return true;
	return /^\*\.[^\s/]+$/.test(token);
}

export function parseRuleConditionAndScope(
	frontmatter: RuleFrontmatter,
): Pick<Rule, "condition" | "astCondition" | "question" | "scope"> {
	const rawCondition = frontmatter.condition ?? frontmatter.ttsr_trigger ?? frontmatter.ttsrTrigger;
	const parsedCondition = normalizeRuleField(rawCondition);
	const astCondition = normalizeRuleField(frontmatter.astCondition);
	const parsedScope = normalizeScopeField(frontmatter.scope);

	const inferredScope: string[] = [];
	const condition: string[] = [];
	for (const token of parsedCondition ?? []) {
		if (isLikelyFileGlob(token)) {
			for (const toolName of CONDITION_GLOB_SCOPE_TOOLS) inferredScope.push(`tool:${toolName}(${token})`);
			continue;
		}
		condition.push(token);
	}
	if (condition.length === 0 && inferredScope.length > 0) condition.push(".*");

	const scope = [...(parsedScope ?? []), ...inferredScope];
	return {
		condition: condition.length > 0 ? Array.from(new Set(condition)) : undefined,
		astCondition,
		question: typeof frontmatter.question === "string" ? frontmatter.question.trim() || undefined : undefined,
		scope: scope.length > 0 ? Array.from(new Set(scope)) : undefined,
	};
}

const INLINE_FLAG_PREFIX = /^\(\?([a-z]+)\)/;
const TRANSLATABLE_INLINE_FLAGS = /^[ims]+$/;

// Greedy lookahead chains only match at zero.
function canMatchWholeBufferFromStart(source: string): boolean {
	let offset = 0;
	let lookaheads = 0;
	const prefix = "(?=[\\s\\S]*";
	while (source.startsWith(prefix, offset) && source[offset + prefix.length] !== "?") {
		let depth = 1;
		let inCharacterClass = false;
		let end = -1;
		for (let index = offset + 3; index < source.length; index++) {
			const char = source[index];
			if (char === "\\") {
				index++;
				continue;
			}
			if (inCharacterClass) {
				if (char === "]") inCharacterClass = false;
				continue;
			}
			if (char === "[") {
				inCharacterClass = true;
				continue;
			}
			if (char === "(") {
				depth++;
				continue;
			}
			if (char !== ")") continue;
			depth--;
			if (depth === 0) {
				end = index + 1;
				break;
			}
		}
		if (end === -1) return false;
		offset = end;
		lookaheads++;
	}
	return lookaheads > 0 && offset === source.length;
}

function optimizeRuleCondition(condition: RegExp): RegExp {
	if (condition.sticky || !canMatchWholeBufferFromStart(condition.source)) return condition;
	return new RegExp(condition.source, `${condition.flags}y`);
}

// JS RegExp rejects PCRE `(?i)` prefixes.
export function compileRuleCondition(pattern: string): RegExp {
	const match = INLINE_FLAG_PREFIX.exec(pattern);
	if (match && TRANSLATABLE_INLINE_FLAGS.test(match[1])) {
		const flags = Array.from(new Set(match[1])).join("");
		return optimizeRuleCondition(new RegExp(pattern.slice(match[0].length), flags));
	}
	return optimizeRuleCondition(new RegExp(pattern));
}

export function buildRule(
	name: string,
	body: string,
	frontmatter: RuleFrontmatter,
	filePath: string,
	level: RuleLevel,
): Rule {
	const { condition, astCondition, question, scope } = parseRuleConditionAndScope(frontmatter);
	let globs: string[] | undefined;
	if (Array.isArray(frontmatter.globs)) {
		globs = frontmatter.globs.filter((item): item is string => typeof item === "string");
	} else if (typeof frontmatter.globs === "string") {
		globs = [frontmatter.globs];
	}
	const rawMode = frontmatter.interruptMode;
	const interruptMode =
		rawMode === "never" || rawMode === "prose-only" || rawMode === "tool-only" || rawMode === "always"
			? rawMode
			: undefined;
	return {
		name: name.replace(/\.(md|mdc)$/, ""),
		path: filePath,
		content: body,
		level,
		globs,
		description: typeof frontmatter.description === "string" ? frontmatter.description : undefined,
		condition,
		astCondition,
		question,
		scope,
		interruptMode,
	};
}
