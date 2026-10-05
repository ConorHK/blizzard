// Ported from oh-my-pi (MIT): modes/controllers/omfg-rule.ts.
import * as path from "node:path";
import { type Judge, judgeRules } from "./judge.ts";
import { TtsrManager, type AstMatcher, type TtsrOutput } from "./manager.ts";
import { buildRule, compileRuleCondition, type Rule, type RuleLevel } from "./rule.ts";

export interface ParsedGeneratedRule {
	rule: Rule;
	fileContent: string;
}

export type GeneratedRuleParseResult = ParsedGeneratedRule | { error: string };

export interface RuleHistoryValidation {
	matched: boolean;
	feedback?: string;
	/** Regenerating cannot conjure a judge. */
	judgeUnavailable?: boolean;
}

export interface ParsedRuleHistoryValidation {
	candidate: ParsedGeneratedRule;
	validation: RuleHistoryValidation;
	repairedCondition: boolean;
}

interface GeneratedRulePayload {
	name: string;
	description: string;
	condition?: string[];
	astCondition?: string[];
	question?: string;
	scope: string[];
	body: string;
}

const JSON_FENCE_PATTERN = /```(?:json)?\s*([\s\S]*?)```/i;
const MAX_JUDGED_VALIDATION_OUTPUTS = 8;

export function extractGeneratedRuleJson(text: string): string | null {
	const trimmed = text.trim();
	const fenced = JSON_FENCE_PATTERN.exec(trimmed);
	if (fenced?.[1]) {
		const fencedObject = extractBalancedJsonObject(fenced[1]);
		if (fencedObject) return fencedObject;
	}
	return extractBalancedJsonObject(trimmed);
}

export function sanitizeRuleName(rawName: string): string {
	return rawName
		.trim()
		.toLowerCase()
		.replace(/["'`]/g, "")
		.replace(/[^a-z0-9_-]+/g, "-")
		.replace(/-+/g, "-")
		.replace(/^[-_]+|[-_]+$/g, "");
}

function ruleFromPayload(payload: GeneratedRulePayload, filePath: string, level: RuleLevel): Rule {
	return buildRule(
		payload.name,
		payload.body.trim().replace(/\r\n?/g, "\n"),
		{
			description: payload.description,
			condition: payload.condition,
			astCondition: payload.astCondition,
			question: payload.question,
			scope: payload.scope,
		},
		filePath,
		level,
	);
}

/** Re-point a candidate at its saved file. */
export function withPath(rule: Rule, filePath: string, level: RuleLevel): Rule {
	return { ...rule, path: filePath, level };
}

function normalizeConditionRegex(condition: string): { condition: string } | { error: string } {
	try {
		compileRuleCondition(condition);
		return { condition };
	} catch (originalError) {
		const repaired = unescapeRegexConditionOnce(condition);
		if (repaired !== condition) {
			try {
				compileRuleCondition(repaired);
				return { condition: repaired };
			} catch {}
		}
		const message = originalError instanceof Error ? originalError.message : String(originalError);
		return { error: `Invalid condition regex ${JSON.stringify(condition)}: ${message}` };
	}
}

function unescapeRegexConditionOnce(condition: string): string {
	return condition.replace(/\\\\/g, "\\");
}

export function parseGeneratedRule(text: string): GeneratedRuleParseResult {
	const jsonText = extractGeneratedRuleJson(text);
	if (!jsonText) return { error: "Missing generated rule JSON object" };
	const payloadResult = parseGeneratedRulePayload(jsonText);
	if ("error" in payloadResult) return payloadResult;

	const ruleName = sanitizeRuleName(payloadResult.name);
	if (ruleName.length === 0) return { error: "Rule name must contain at least one letter or digit" };

	let condition: string[] | undefined;
	if (payloadResult.condition) {
		const normalized: string[] = [];
		for (const raw of payloadResult.condition) {
			const result = normalizeConditionRegex(raw);
			if ("error" in result) return result;
			if (!normalized.includes(result.condition)) normalized.push(result.condition);
		}
		condition = normalized;
	}

	const payload = { ...payloadResult, name: ruleName, condition };
	const rule = ruleFromPayload(payload, path.join(process.cwd(), `${ruleName}.md`), "project");
	if (!new TtsrManager().addRule(rule)) return { error: "Rule has no valid trigger or reachable scope" };
	return { rule, fileContent: assembleRuleMarkdown(payload) };
}

function extractBalancedJsonObject(text: string): string | null {
	const start = text.indexOf("{");
	if (start === -1) return null;
	let depth = 0;
	let inString = false;
	let escaped = false;
	for (let i = start; i < text.length; i++) {
		const char = text[i];
		if (inString) {
			if (escaped) escaped = false;
			else if (char === "\\") escaped = true;
			else if (char === '"') inString = false;
			continue;
		}
		if (char === '"') inString = true;
		else if (char === "{") depth++;
		else if (char === "}") {
			depth--;
			if (depth === 0) return text.slice(start, i + 1);
		}
	}
	return null;
}

function parseGeneratedRulePayload(jsonText: string): GeneratedRulePayload | { error: string } {
	let parsed: unknown;
	try {
		parsed = JSON.parse(jsonText);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { error: `Generated rule JSON is invalid: ${message}` };
	}
	if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
		return { error: "Generated rule JSON must be an object" };
	}
	const object = parsed as Record<string, unknown>;
	const rawName = stringField(object, "name");
	if (!rawName) return { error: "Generated rule JSON must include a non-empty name" };
	const description = stringField(object, "description") ?? stringField(object, "desc");
	if (!description) return { error: "Generated rule JSON must include a non-empty description" };
	const condition = stringArrayField(object, "condition") ?? stringArrayField(object, "cond");
	const astCondition = stringArrayField(object, "astCondition");
	const question = stringField(object, "question");
	if (!condition && !astCondition && !question) {
		return { error: "Generated rule JSON must include a `condition`, `astCondition`, or `question`" };
	}
	const scope = stringArrayField(object, "scope");
	if (!scope || scope.length === 0) return { error: "Generated rule JSON must include at least one scope" };
	const body = stringField(object, "body");
	if (!body) return { error: "Generated rule JSON must include a non-empty body" };
	return { name: rawName, description, condition, astCondition, question, scope, body };
}

function stringField(object: Record<string, unknown>, key: string): string | undefined {
	const value = object[key];
	if (typeof value !== "string") return undefined;
	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : undefined;
}

function stringArrayField(object: Record<string, unknown>, key: string): string[] | undefined {
	const value = object[key];
	if (typeof value === "string") {
		const trimmed = value.trim();
		return trimmed.length > 0 ? [trimmed] : undefined;
	}
	if (!Array.isArray(value)) return undefined;
	const items: string[] = [];
	for (const item of value) {
		if (typeof item !== "string") continue;
		const trimmed = item.trim();
		if (trimmed.length > 0 && !items.includes(trimmed)) items.push(trimmed);
	}
	return items.length > 0 ? items : undefined;
}

function assembleRuleMarkdown(payload: GeneratedRulePayload): string {
	const lines = ["---", `name: ${payload.name}`, `description: ${JSON.stringify(payload.description)}`];
	if (payload.condition) lines.push(`condition: ${formatFrontmatterStringArray(payload.condition)}`);
	if (payload.astCondition) lines.push(`astCondition: ${formatFrontmatterStringArray(payload.astCondition)}`);
	if (payload.question) lines.push(`question: ${JSON.stringify(payload.question)}`);
	lines.push(
		`scope: ${formatFrontmatterStringArray(payload.scope)}`,
		"---",
		"",
		payload.body.trim().replace(/\r\n?/g, "\n"),
	);
	return `${lines.join("\n")}\n`;
}

function formatFrontmatterStringArray(values: readonly string[]): string {
	if (values.length === 1) return JSON.stringify(values[0]);
	return `[${values.map(value => JSON.stringify(value)).join(", ")}]`;
}

export async function validateRuleAgainstAssistantHistory(
	rule: Rule,
	outputs: readonly TtsrOutput[],
	judge: Judge | undefined,
	astMatch?: AstMatcher,
): Promise<RuleHistoryValidation> {
	const manager = new TtsrManager(undefined, astMatch);
	if (!manager.addRule(rule)) {
		return {
			matched: false,
			feedback: "TTSR rejected the rule: it has no valid trigger or its scope cannot reach any stream.",
		};
	}
	if (rule.question !== undefined) return validateQuestionRule(rule, rule.question, manager, outputs, judge);

	const matches: TtsrOutput[] = [];
	for (const output of outputs) {
		if (output.content.length === 0) continue;
		manager.resetBuffer();
		if (
			manager.checkSnapshot(output.content, output.context).length > 0 ||
			(await manager.checkAstSnapshot(output.content, output.context)).length > 0
		) {
			matches.push(output);
		}
	}
	if (matches.length === 0) return { matched: false, feedback: buildNoMatchFeedback(rule, outputs) };
	const scopeFeedback = buildScopeFeedback(rule, matches);
	if (scopeFeedback) return { matched: false, feedback: scopeFeedback };
	return { matched: true };
}

async function validateQuestionRule(
	rule: Rule,
	question: string,
	manager: TtsrManager,
	outputs: readonly TtsrOutput[],
	judge: Judge | undefined,
): Promise<RuleHistoryValidation> {
	const reachable: TtsrOutput[] = [];
	for (const output of outputs) {
		if ((await manager.judgedCandidates(output.content, output.context)).length > 0) reachable.push(output);
	}
	if (reachable.length === 0) return { matched: false, feedback: buildNoMatchFeedback(rule, outputs) };
	if (!judge) {
		return {
			matched: false,
			judgeUnavailable: true,
			feedback: "No judge model is available (see `judge` in ttsr.json), so the question could not be confirmed.",
		};
	}
	const recent = reachable.slice(-MAX_JUDGED_VALIDATION_OUTPUTS);
	let verdicts: Rule[][];
	try {
		verdicts = await Promise.all(recent.map(output => judgeRules(judge, output, [{ rule, question }])));
	} catch (error) {
		return {
			matched: false,
			judgeUnavailable: true,
			feedback: `The judge failed: ${error instanceof Error ? error.message : String(error)}`,
		};
	}
	if (verdicts.some(flagged => flagged.length > 0)) return { matched: true };
	return {
		matched: false,
		feedback: `The judge answered no to question ${JSON.stringify(question)} for every in-scope output checked (${recent
			.map(output => output.subject)
			.join(
				", ",
			)}). Rephrase the question so the offending output clearly answers yes, or prefer a \`condition\`/\`astCondition\` if the offending output has a literal or structural signature.`,
	};
}

export async function validateParsedRuleAgainstAssistantHistory(
	candidate: ParsedGeneratedRule,
	outputs: readonly TtsrOutput[],
	judge: Judge | undefined,
	astMatch?: AstMatcher,
): Promise<ParsedRuleHistoryValidation> {
	const validation = await validateRuleAgainstAssistantHistory(candidate.rule, outputs, judge, astMatch);
	if (validation.matched) return { candidate, validation, repairedCondition: false };
	const repaired = repairEscapedConditions(candidate);
	if (!repaired) return { candidate, validation, repairedCondition: false };
	const repairedValidation = await validateRuleAgainstAssistantHistory(repaired.rule, outputs, judge, astMatch);
	if (repairedValidation.matched) return { candidate: repaired, validation: repairedValidation, repairedCondition: true };
	return { candidate, validation, repairedCondition: false };
}

function repairEscapedConditions(candidate: ParsedGeneratedRule): ParsedGeneratedRule | undefined {
	const { rule } = candidate;
	const currentConditions = rule.condition;
	if (!currentConditions || currentConditions.length === 0) return undefined;
	const repairedConditions = currentConditions.map(unescapeRegexConditionOnce);
	if (repairedConditions.every((condition, index) => condition === currentConditions[index])) return undefined;
	const scope = rule.scope;
	if (!scope || scope.length === 0) return undefined;
	const payload: GeneratedRulePayload = {
		name: rule.name,
		description: rule.description ?? rule.name,
		condition: repairedConditions,
		astCondition: rule.astCondition,
		question: rule.question,
		scope,
		body: rule.content,
	};
	return { rule: ruleFromPayload(payload, rule.path, rule.level), fileContent: assembleRuleMarkdown(payload) };
}

function describeTriggers(rule: Rule): string {
	const parts: string[] = [];
	if (rule.condition) parts.push(`condition ${formatRuleList(rule.condition)}`);
	if (rule.astCondition) parts.push(`astCondition ${formatRuleList(rule.astCondition)}`);
	if (rule.question) parts.push(`question ${JSON.stringify(rule.question)}`);
	return parts.join(" / ");
}

function buildNoMatchFeedback(rule: Rule, outputs: readonly TtsrOutput[]): string {
	const hints = extractConditionHints([...(rule.condition ?? []), ...(rule.astCondition ?? [])]);
	const lines = [
		rule.question
			? `No assistant output within scope ${formatRuleList(rule.scope)} passed ${describeTriggers(rule)}; the question was never asked.`
			: `No assistant output matched ${describeTriggers(rule)} within scope ${formatRuleList(rule.scope)}.`,
	];
	if (outputs.length === 0) {
		lines.push("No assistant replies, reasoning, or tool calls were available to check.");
		return lines.join("\n");
	}
	lines.push("Checked outputs:");
	const max = Math.min(outputs.length, 5);
	for (let i = 0; i < max; i++) {
		const output = outputs[i];
		lines.push(`- ${output.subject}: ${JSON.stringify(excerptForOutput(output.content, hints))}`);
	}
	if (outputs.length > max) lines.push(`- ... ${outputs.length - max} more output(s)`);
	lines.push(
		'edit/write calls are checked as the written source text; other tool calls as serialized JSON arguments, where quotes appear escaped (\\").',
	);
	lines.push("If the trigger looks right, fix the scope so it reaches the offending tool and file glob.");
	return lines.join("\n");
}

function buildScopeFeedback(rule: Rule, matches: readonly TtsrOutput[]): string | undefined {
	const toolMatch = matches.find(
		match => match.context.source === "tool" && match.context.toolName && extensionGlob(match.context.filePaths),
	);
	if (!toolMatch) return undefined;
	const recommendedScope = recommendedToolScope(toolMatch);
	if (!recommendedScope) return undefined;
	const scope = rule.scope ?? [];
	let hasBroadToolScope = scope.length === 0;
	let hasTextScope = false;
	for (const rawToken of scope) {
		const token = rawToken.trim().toLowerCase();
		if (token === "tool" || token === "toolcall") hasBroadToolScope = true;
		else if (token === "text") hasTextScope = true;
	}
	if (!hasBroadToolScope && !hasTextScope) return undefined;
	const problems: string[] = [];
	if (hasBroadToolScope) {
		problems.push(`scope ${formatRuleList(rule.scope)} is broader than the matching file-specific tool call`);
	}
	if (hasTextScope) problems.push("scope includes `text`, but the offending content was confirmed in tool arguments");
	return `The trigger matched the ${toolMatch.subject}, but ${problems.join("; ")}. Use a narrow scope such as ${JSON.stringify(
		recommendedScope,
	)} and do not repeat the failed scope ${formatRuleList(rule.scope)}.`;
}

function recommendedToolScope(output: TtsrOutput): string | undefined {
	const toolName = output.context.toolName;
	const glob = extensionGlob(output.context.filePaths);
	if (!toolName || !glob) return undefined;
	return `tool:${toolName}(${glob})`;
}

function extensionGlob(filePaths: readonly string[] | undefined): string | undefined {
	for (const filePath of filePaths ?? []) {
		const extension = path.extname(filePath.replaceAll("\\", "/")).toLowerCase();
		if (extension.length > 1) return `*${extension}`;
	}
	return undefined;
}

function formatRuleList(values: readonly string[] | undefined): string {
	if (!values || values.length === 0) return "<default>";
	return values.map(value => JSON.stringify(value)).join(", ");
}

function extractConditionHints(conditions: readonly string[]): string[] {
	const hints: string[] = [];
	for (const condition of conditions) {
		for (const match of condition.match(/[A-Za-z_][A-Za-z0-9_]{2,}/g) ?? []) {
			const normalized = match.toLowerCase();
			if (["tool", "text", "any", "true", "false"].includes(normalized)) continue;
			if (!hints.includes(normalized)) hints.push(normalized);
		}
	}
	return hints;
}

function excerptForOutput(text: string, hints: readonly string[]): string {
	const normalized = text.replace(/\s+/g, " ");
	if (normalized.length <= 260) return normalized;
	const lower = normalized.toLowerCase();
	let bestIndex = -1;
	for (const hint of hints) {
		const index = lower.indexOf(hint);
		if (index !== -1 && (bestIndex === -1 || index < bestIndex)) bestIndex = index;
	}
	if (bestIndex === -1) return `${normalized.slice(0, 260)}...`;
	const start = Math.max(0, bestIndex - 120);
	const end = Math.min(normalized.length, bestIndex + 140);
	return `${start > 0 ? "..." : ""}${normalized.slice(start, end)}${end < normalized.length ? "..." : ""}`;
}
