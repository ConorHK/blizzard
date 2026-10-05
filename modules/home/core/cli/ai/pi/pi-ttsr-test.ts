import assert from "node:assert/strict";
import { test } from "node:test";
import { astGrepMatcher } from "./ttsr/ast.ts";
import { chatJudge, classifierJudge, judgeRules } from "./ttsr/judge.ts";
import { TtsrManager, type TtsrOutput } from "./ttsr/manager.ts";
import { parseGeneratedRule, validateParsedRuleAgainstAssistantHistory } from "./ttsr/omfg-rule.ts";
import { historyOutputs, TtsrToolInspector } from "./ttsr/outputs.ts";
import { render } from "./ttsr/prompts.ts";
import { buildRule, compileRuleCondition, parseRuleConditionAndScope, type Rule } from "./ttsr/rule.ts";

const astMatch = astGrepMatcher(process.env.PI_TTSR_AST_GREP ?? "ast-grep");
const inspector = new TtsrToolInspector(() => "/repo");

function rule(name: string, frontmatter: Record<string, unknown>, body = `Do not ${name}.`): Rule {
	return buildRule(`${name}.md`, body, frontmatter, `/rules/${name}.md`, "user");
}

function assistant(...content: object[]) {
	return { role: "assistant", content, timestamp: 1 };
}

test("glob condition becomes edit/write scope", () => {
	const parsed = parseRuleConditionAndScope({ condition: "*.rs" });
	assert.deepEqual(parsed.condition, [".*"]);
	assert.deepEqual(parsed.scope, ["tool:edit(*.rs)", "tool:write(*.rs)"]);
});

test("inline (?i) flag compiles", () => {
	assert.ok(compileRuleCondition("(?i)tests? pass").test("Tests PASS"));
});

test("text rule matches across stream chunks", () => {
	const manager = new TtsrManager();
	manager.addRule(rule("claims", { condition: "all tests pass", scope: "text" }));
	assert.equal(manager.checkDelta("all te", { source: "text" }).length, 0);
	assert.equal(manager.checkDelta("sts pass", { source: "text" }).length, 1);
	manager.resetBuffer();
	assert.equal(manager.checkDelta("sts pass", { source: "text" }).length, 0);
});

test("tool scope with path glob", () => {
	const manager = new TtsrManager();
	manager.addRule(rule("ts-any", { condition: ": any", scope: "tool:edit(*.ts)" }));
	const call = { id: "1", name: "edit", arguments: { path: "src/a.ts", edits: [{ oldText: "x", newText: "let y: any" }] } };
	const out = inspector.toolCallOutput(call, 0);
	assert.equal(out.content, "let y: any");
	assert.ok(out.context.filePaths?.includes("src/a.ts"));
	assert.equal(manager.checkSnapshot(out.content, out.context).length, 1);
	const md = inspector.toolCallOutput({ ...call, arguments: { ...call.arguments, path: "a.md" } }, 0);
	assert.equal(manager.checkSnapshot(md.content, md.context).length, 0);
	assert.equal(manager.checkSnapshot("x: any", { source: "text" }).length, 0);
});

test("repeat once blocks, after-gap re-arms", () => {
	const once = new TtsrManager();
	const r = rule("r", { condition: "bad", scope: "text" });
	once.addRule(r);
	once.markInjected([r]);
	assert.equal(once.checkSnapshot("bad", { source: "text" }).length, 0);

	const gap = new TtsrManager({ repeatMode: "after-gap", repeatGap: 2 });
	gap.addRule(r);
	gap.markInjected([r]);
	gap.incrementMessageCount();
	assert.equal(gap.checkSnapshot("bad", { source: "text" }).length, 0);
	gap.incrementMessageCount();
	assert.equal(gap.checkSnapshot("bad", { source: "text" }).length, 1);
});

test("removeRule clears text matching", () => {
	const manager = new TtsrManager();
	manager.addRule(rule("r", { condition: "bad", scope: "text" }));
	manager.removeRule("r");
	assert.equal(manager.checkDelta("bad", { source: "text" }).length, 0);
	assert.equal(manager.hasRules(), false);
});

test("ast condition matches written source", async () => {
	const manager = new TtsrManager(undefined, astMatch);
	manager.addRule(rule("no-any-const", { astCondition: "const $X: any = $Y", scope: "tool:write(*.ts)" }));
	const ctx = inspector.matchContext({ id: "2", name: "write", arguments: { path: "a.ts" } }, 0);
	assert.equal((await manager.checkAstSnapshot("const x: any = 1;", ctx)).length, 1);
	manager.resetBuffer();
	assert.equal((await manager.checkAstSnapshot("const x: number = 1;", ctx)).length, 0);
});

test("non edit/write tools are checked as JSON", () => {
	const out = inspector.toolCallOutput({ id: "3", name: "bash", arguments: { command: "rm -rf /" } }, 0);
	assert.equal(out.content, '{"command":"rm -rf /"}');
	assert.equal(out.subject, "`bash` call");
});

test("render handles if blocks", () => {
	assert.ok(!render("omfg-user", { complaint: "c" }).includes("Failed attempts"));
	assert.ok(render("omfg-user", { complaint: "c", feedback: "f", previousRule: "p" }).includes("Failed attempts"));
});

const history = [
	assistant(
		{ type: "text", text: "Writing the file now." },
		{ type: "toolCall", id: "w1", name: "write", arguments: { path: "lib/x.rb", content: "eval(input)" } },
	),
];

test("generated rule validates against history", async () => {
	const reply =
		'```json\n{"name": "Ruby Eval", "description": "No eval", "condition": "\\\\beval\\\\s*\\\\(", "scope": ["tool:write(*.rb)"], "body": "Never eval."}\n```';
	const parsed = parseGeneratedRule(reply);
	assert.ok(!("error" in parsed), JSON.stringify(parsed));
	assert.equal(parsed.rule.name, "ruby-eval");
	assert.match(parsed.fileContent, /^---\nname: ruby-eval\n/);
	const outputs = historyOutputs(history, inspector);
	const result = await validateParsedRuleAgainstAssistantHistory(parsed, outputs, undefined, astMatch);
	assert.equal(result.validation.matched, true, result.validation.feedback);
});

test("broad scope gets narrowing feedback", async () => {
	const parsed = parseGeneratedRule('{"name":"e","description":"d","condition":"eval","scope":"tool","body":"b"}');
	assert.ok(!("error" in parsed));
	const result = await validateParsedRuleAgainstAssistantHistory(parsed, historyOutputs(history, inspector), undefined);
	assert.equal(result.validation.matched, false);
	assert.match(result.validation.feedback ?? "", /tool:write\(\*\.rb\)/);
});

test("question rule needs a judge", async () => {
	const parsed = parseGeneratedRule(
		'{"name":"q","description":"d","question":"Does it eval user input?","scope":"tool:write(*.rb)","body":"b"}',
	);
	assert.ok(!("error" in parsed));
	const outputs = historyOutputs(history, inspector);
	const none = await validateParsedRuleAgainstAssistantHistory(parsed, outputs, undefined);
	assert.equal(none.validation.judgeUnavailable, true);
	const yes = chatJudge("fake", async prompt => {
		assert.match(prompt, /eval\(input\)/);
		return 'Sure: {"q0": 0.93}';
	});
	const judged = await validateParsedRuleAgainstAssistantHistory(parsed, outputs, yes);
	assert.equal(judged.validation.matched, true);
	const no = chatJudge("fake", async () => '{"q0": 0.1}');
	assert.equal((await validateParsedRuleAgainstAssistantHistory(parsed, outputs, no)).validation.matched, false);
});

test("classifier judge maps bool probabilities", async () => {
	const r = rule("q", { question: "Q?" });
	const judge = classifierJudge("jev", async context => {
		assert.equal(context.questions.q0.type, "bool");
		return { answers: { q0: { probability: 0.8 } }, stopReason: "stop" };
	});
	const output: TtsrOutput = { content: "x", context: { source: "text" }, subject: "reply" };
	assert.deepEqual(await judgeRules(judge, output, [{ rule: r, question: "Q?" }]), [r]);
});
