import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { test } from "node:test";
import {
	logLine,
	parseRef,
	projectFor,
	readFrontmatter,
	renderTask,
	renderWorker,
	replyHeadline,
	setFrontmatter,
	slugify,
	taskNotePath,
	workerLine,
	workerNotePath,
	workerSummary,
	yamlValue,
} from "./ogham/vault.ts";

const now = new Date(2026, 9, 20, 14, 5);
const ref = { project: "blizzard", slug: "fix-sync" };

test("slugs and refs", () => {
	assert.equal(slugify("  Fix the Sync, again! "), "fix-the-sync-again");
	assert.equal(slugify("!!!"), "task");
	assert.equal(slugify("a".repeat(80)).length, 60);
	assert.deepEqual(parseRef("DotFiles/Fix Sync"), { project: "dotfiles", slug: "fix-sync" });
	assert.equal(parseRef("no-slash"), undefined);
	assert.equal(parseRef("a/b/c"), undefined);
	assert.equal(taskNotePath(ref), "projects/blizzard/fix-sync/fix-sync.md");
	assert.equal(workerNotePath(ref, "01a15dd2-70e3"), "projects/blizzard/fix-sync/workers/01a15dd2.md");
});

test("project is the repo root name", () => {
	const root = mkdtempSync(path.join(tmpdir(), "ogham-"));
	const repo = path.join(root, "My Repo");
	mkdirSync(path.join(repo, ".jj"), { recursive: true });
	mkdirSync(path.join(repo, "src", "deep"), { recursive: true });
	assert.equal(projectFor(path.join(repo, "src", "deep")), "my-repo");
	const loose = path.join(root, "loose");
	mkdirSync(loose);
	assert.equal(projectFor(loose), "loose");
});

test("yaml values stay typed or get quoted", () => {
	assert.equal(yamlValue("active"), "active");
	assert.equal(yamlValue("2026-10-20T14:05"), "2026-10-20T14:05");
	assert.equal(yamlValue("[[fix-sync]]"), '"[[fix-sync]]"');
	assert.equal(yamlValue("w2:p1P"), '"w2:p1P"');
	assert.equal(yamlValue("true"), '"true"');
});

test("frontmatter updates keep the body", () => {
	const note = renderWorker({ ref, role: "worker", session: "01a15dd2-70e3", cwd: "/repo", pane: "w2:p1P", now });
	assert.match(note, /^---\ntype: worker\ntask: blizzard\/fix-sync\n/);
	assert.doesNotMatch(note, /intercom:/);
	const updated = setFrontmatter(note, { status: "working", extra: "x y" });
	assert.match(updated, /\nstatus: working\n/);
	assert.match(updated, /\nextra: "x y"\n---\n/);
	assert.equal(updated.split("## Log").length, 2);
	assert.equal(setFrontmatter("body\n", { a: "b" }), "---\na: b\n---\nbody\n");
});

test("task note ends with the workers list", () => {
	const note = renderTask(ref, "Fix sync", "Make it work", now);
	assert.match(note, /^---\ntype: task\nproject: blizzard\nstatus: active\ncreated: 2026-10-20T14:05\n---\n# Fix sync\n/);
	assert.match(note, /## Goal\n\nMake it work\n\n## Log\n\n## Workers\n\n$/);
	assert.equal(
		workerLine({ session: "01a15dd2-70e3", role: "worker", pane: "w2:p1P" }),
		"- [01a15dd2](workers/01a15dd2.md) worker, pane w2:p1P\n",
	);
	assert.equal(workerLine({ session: "01a15dd2-70e3", role: "orchestrator" }), "- [01a15dd2](workers/01a15dd2.md) orchestrator\n");
});

test("worker summaries read back the frontmatter", () => {
	const note = renderWorker({ ref, role: "orchestrator", session: "01a15dd2-70e3", cwd: "/r", pane: "w2:p1P", intercom: "abc", now });
	const fields = readFrontmatter(setFrontmatter(note, { status: "working" }));
	assert.equal(fields.pane, "w2:p1P");
	assert.equal(workerSummary(fields), "01a15dd2 orchestrator working pane w2:p1P intercom abc updated 2026-10-20T14:05");
	assert.deepEqual(readFrontmatter("no frontmatter"), {});
});

test("log lines use the reply headline", () => {
	const messages = [
		{ role: "assistant", content: [{ type: "text", text: "old" }] },
		{ role: "user", content: "next" },
		{ role: "assistant", content: [{ type: "toolCall" }, { type: "text", text: "\n\n  Sync fixed: push works.\nDetails" }] },
	];
	assert.equal(replyHeadline(messages), "Sync fixed: push works.");
	assert.equal(replyHeadline([{ role: "user", content: "hi" }]), undefined);
	assert.equal(logLine(now, "a\nb"), "- 14:05 a b\n");
	assert.equal(logLine(now, "x".repeat(200)).length, "- 14:05 ".length + 160 + 1);
});
