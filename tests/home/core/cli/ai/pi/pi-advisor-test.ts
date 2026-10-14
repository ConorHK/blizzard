import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { test } from "node:test";
import { contextFiles, watchdogFiles } from "./advisor/context.ts";
import { deliveryChannel, EmissionGuard } from "./advisor/guard.ts";
import { renderAdvisory, renderUpdate, WIP_MARKER } from "./advisor/transcript.ts";

test("guard drops noise and duplicates", () => {
	const guard = new EmissionGuard();
	assert.equal(guard.admit("LGTM!", { rank: 1, pending: false }).reason, "noise");
	assert.equal(guard.admit("Check the null path in foo()", { rank: 1, pending: false }).accepted, true);
	assert.equal(guard.admit("check the NULL path in foo().", { rank: 1, pending: false }).reason, "duplicate");
	assert.equal(guard.admit("check the null path in foo()", { rank: 3, pending: false }).accepted, true);
});

test("guard budget: blockers exempt, higher rank displaces pending", () => {
	const guard = new EmissionGuard(2);
	assert.ok(guard.admit("a1 nit", { rank: 1, pending: true }).accepted);
	assert.ok(guard.admit("a2 nit", { rank: 1, pending: true }).accepted);
	assert.equal(guard.admit("a3 nit", { rank: 1, pending: true }).reason, "rate-limit");
	assert.equal(guard.admit("a4 concern", { rank: 2, pending: true }).displacedKey, "a1 nit");
	assert.ok(guard.admit("a5 blocker", { rank: 3, pending: false }).accepted);
	guard.beginUpdate();
	assert.ok(guard.admit("a6 nit", { rank: 1, pending: true }).accepted);
});

test("delivery channels", () => {
	const base = { autoResumeSuppressed: false, streaming: false, terminalAnswer: false, immune: false };
	assert.equal(deliveryChannel({ ...base, severity: "nit" }), "aside");
	assert.equal(deliveryChannel({ ...base, severity: "concern" }), "steer");
	assert.equal(deliveryChannel({ ...base, severity: "concern", terminalAnswer: true }), "preserve");
	assert.equal(deliveryChannel({ ...base, severity: "blocker", terminalAnswer: true }), "steer");
	assert.equal(deliveryChannel({ ...base, severity: "blocker", autoResumeSuppressed: true }), "preserve");
	assert.equal(deliveryChannel({ ...base, severity: "concern", immune: true }), "aside");
	assert.equal(deliveryChannel({ ...base, severity: "blocker", immune: true }), "steer");
});

test("update renders turns and skips own notes", () => {
	const text = renderUpdate(
		[
			{ type: "message", message: { role: "user", content: "fix it" } },
			{
				type: "message",
				message: {
					role: "assistant",
					content: [
						{ type: "thinking", thinking: "plan" },
						{ type: "toolCall", name: "read", arguments: { path: "a.ts" } },
					],
				},
			},
			{ type: "message", message: { role: "toolResult", toolName: "read", content: [{ type: "text", text: "x".repeat(3000) }] } },
			{ type: "custom_message", customType: "advisor-note", content: "old advice" },
			{ type: "custom_message", customType: "rewind-report", content: "found the bug" },
		],
		true,
	);
	assert.ok(text);
	assert.match(text, /^### Session update/);
	assert.match(text, /\*\*User:\*\*\nfix it/);
	assert.doesNotMatch(text, /plan/);
	assert.match(text, /Tool call `read`/);
	assert.match(text, /\[elided 500 chars\]/);
	assert.doesNotMatch(text, /old advice/);
	assert.match(text, /Checkpoint report:\*\*\nfound the bug/);
	assert.ok(text.endsWith(WIP_MARKER));
	assert.equal(renderUpdate([{ type: "custom_message", customType: "advisor-note", content: "x" }], false), undefined);
});

test("advisory escapes xml", () => {
	assert.match(renderAdvisory("a < b", "nit"), /a &lt; b/);
});

test("context and watchdog discovery stops at repo root", () => {
	const root = mkdtempSync(path.join(tmpdir(), "advisor-"));
	const agentDir = path.join(root, "agent");
	const repo = path.join(root, "repo");
	const sub = path.join(repo, "pkg");
	mkdirSync(agentDir);
	mkdirSync(path.join(repo, ".git"), { recursive: true });
	mkdirSync(path.join(sub, ".pi"), { recursive: true });
	writeFileSync(path.join(root, "AGENTS.md"), "outside");
	writeFileSync(path.join(agentDir, "AGENTS.md"), "global");
	writeFileSync(path.join(repo, "AGENTS.md"), "repo");
	writeFileSync(path.join(sub, "CLAUDE.md"), "sub");
	writeFileSync(path.join(agentDir, "WATCHDOG.md"), "user watch");
	writeFileSync(path.join(sub, ".pi", "WATCHDOG.md"), "sub watch");
	assert.deepEqual(contextFiles(sub, agentDir, true).map(f => f.content), ["global", "repo", "sub"]);
	assert.deepEqual(contextFiles(sub, agentDir, false).map(f => f.content), ["global"]);
	assert.deepEqual(watchdogFiles(sub, agentDir, true).map(f => f.content), ["user watch", "sub watch"]);
});
