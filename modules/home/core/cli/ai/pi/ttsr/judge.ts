// Ported from oh-my-pi (MIT): judgeRules in export/ttsr.ts.
import type { JudgedCandidate, TtsrOutput } from "./manager.ts";
import { render } from "./prompts.ts";
import type { Rule } from "./rule.ts";

export const JUDGED_RULE_THRESHOLD = 0.7;
// Caps one judgment; keeps the head.
const MAX_CONTENT_CHARS = 120_000;

export interface Judge {
	readonly label: string;
	/** Yes-probability per candidate, in candidate order. */
	probabilities(output: TtsrOutput, candidates: readonly JudgedCandidate[], signal?: AbortSignal): Promise<number[]>;
}

export interface BoolQuestion {
	type: "bool";
	instructions: string;
	criteria: { true: string; false: string };
}

export type ClassifyFn = (
	context: { state: Record<string, string>; questions: Record<string, BoolQuestion> },
	signal?: AbortSignal,
) => Promise<{ answers: Record<string, { probability?: number }>; stopReason: string; errorMessage?: string }>;

export type AskFn = (prompt: string, signal?: AbortSignal) => Promise<string>;

function clip(content: string): string {
	return content.length <= MAX_CONTENT_CHARS ? content : `${content.slice(0, MAX_CONTENT_CHARS)}\n[truncated]`;
}

export function classifierJudge(label: string, classify: ClassifyFn): Judge {
	return {
		label,
		async probabilities(output, candidates, signal) {
			const questions: Record<string, BoolQuestion> = {};
			for (const [index, candidate] of candidates.entries()) {
				questions[`q${index}`] = {
					type: "bool",
					instructions: candidate.question,
					criteria: { true: "Yes: the output violates the rule.", false: "No: it does not." },
				};
			}
			const result = await classify({ state: { output: output.subject, content: clip(output.content) }, questions }, signal);
			if (result.stopReason !== "stop") throw new Error(result.errorMessage ?? `classifier ${result.stopReason}`);
			return candidates.map((_, index) => result.answers[`q${index}`]?.probability ?? 0);
		},
	};
}

function extractJsonObject(text: string): string | undefined {
	const start = text.indexOf("{");
	const end = text.lastIndexOf("}");
	return start !== -1 && end > start ? text.slice(start, end + 1) : undefined;
}

export function chatJudge(label: string, ask: AskFn): Judge {
	return {
		label,
		async probabilities(output, candidates, signal) {
			const questions = candidates.map((candidate, index) => `- q${index}: ${candidate.question}`).join("\n");
			const reply = await ask(
				render("ttsr-judge", { subject: output.subject, content: clip(output.content), questions }),
				signal,
			);
			const json = extractJsonObject(reply);
			if (!json) throw new Error(`judge reply had no JSON: ${reply.slice(0, 200)}`);
			const parsed = JSON.parse(json) as Record<string, unknown>;
			return candidates.map((_, index) => {
				const value = parsed[`q${index}`];
				const number = typeof value === "number" ? value : typeof value === "boolean" ? Number(value) : 0;
				return Number.isFinite(number) ? number : 0;
			});
		},
	};
}

/** Rules whose question the judge answered yes. */
export async function judgeRules(
	judge: Judge,
	output: TtsrOutput,
	candidates: readonly JudgedCandidate[],
	signal?: AbortSignal,
): Promise<Rule[]> {
	const probabilities = await judge.probabilities(output, candidates, signal);
	return candidates.filter((_, index) => probabilities[index] >= JUDGED_RULE_THRESHOLD).map(c => c.rule);
}
