import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { test } from "node:test";
import {
	findUrl,
	linkSlug,
	parseRef,
	projectFor,
	readFrontmatter,
	renderTask,
	renderWorker,
	setFrontmatter,
	slugify,
	titlePrompt,
	taskNotePath,
	workerLine,
	workerNotePath,
	workerSummary,
	yamlValue,
} from "./ogham/vault.ts";
import {
	appendTopic,
	applyCuration,
	candidateUrls,
	clip,
	firstOpen,
	parseCuration,
	parsePromotion,
	renderIndex,
	renderWin,
	winsFor,
	withoutBookkeeping,
} from "./ogham/curate.ts";
import { parseHits } from "./ogham/knowledge.ts";
import { withLock } from "./ogham/lock.ts";
import { appendLines, getSection, parseNote, renderNote, setSection } from "./ogham/note.ts";

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
	assert.match(updated, /---\n# 01a15dd2\n$/);
	assert.equal(setFrontmatter("body\n", { a: "b" }), "---\na: b\n---\nbody\n");
});

test("task note ends with the workers list", () => {
	const note = renderTask(ref, { title: "Fix sync", goal: "Make it work" }, now);
	assert.match(note, /^---\ntype: task\nproject: blizzard\nstatus: active\ncreated: 2026-10-20T14:05\n---\n# Fix sync\n/);
	assert.match(note, /## Goal\n\nMake it work\n\n## Status\n\n## Next\n\n## Log\n\n## Workers\n$/);
	assert.equal(
		workerLine({ session: "01a15dd2-70e3", role: "worker", pane: "w2:p1P" }),
		"- [01a15dd2](workers/01a15dd2.md) worker, pane w2:p1P",
	);
	assert.equal(workerLine({ session: "01a15dd2-70e3", role: "orchestrator" }), "- [01a15dd2](workers/01a15dd2.md) orchestrator");
});

test("tasks from links keep the URL", () => {
	const url = "https://tickets.example.com/issues/ABC-123";
	const note = renderTask(ref, { title: "ABC-123: Sync breaks", link: url }, now);
	assert.match(note, /\nlink: "https:\/\/tickets\.example\.com\/issues\/ABC-123"\n/);
	assert.match(note, /# ABC-123: Sync breaks\n\nhttps:\/\/tickets\.example\.com\/issues\/ABC-123\n\n## Goal/);
	assert.equal(slugify("ABC-123: Sync breaks"), "abc-123-sync-breaks");

	assert.equal(findUrl(`${url} the sync`), url);
	assert.equal(findUrl("fix the sync"), undefined);
	assert.equal(findUrl(`(see ${url}).`), url);
	assert.equal(findUrl("https://en.wikipedia.org/wiki/Ogham_(script)"), "https://en.wikipedia.org/wiki/Ogham_(script)");
	assert.match(titlePrompt(url), /ogham_task with title "<ID>: <title>" and link "https:\/\/tickets\.example\.com\/issues\/ABC-123"/);

	assert.equal(linkSlug(url), "abc-123");
	assert.equal(linkSlug("https://tickets.example.com/P12345/communication"), "p12345");
	assert.equal(linkSlug("https://example.com/docs/intro"), undefined);
	assert.equal(linkSlug("not a url"), undefined);
	assert.equal(linkSlug("https://code.example.com/reviews/CR-315504661/revisions/1#/diff"), "cr-315504661");
	assert.equal(linkSlug("https://code.example.com/reviews/CR-315504759/revisions/1"), "cr-315504759");
	assert.equal(linkSlug("https://t.example.com/V2429106601/communication"), "v2429106601");
	assert.equal(linkSlug("https://github.com/ConorHK/blizzard/pull/42/commits/9e909e9"), "blizzard-pull-42");
	assert.equal(linkSlug("https://github.com/ConorHK/other/pull/42/files"), "other-pull-42");
	assert.equal(linkSlug("https://docs.example.com/api/v2/guide"), undefined);
	assert.equal(linkSlug("https://jira.example.com/api/v2/issues/ABC-123"), "abc-123");
	assert.equal(linkSlug("https://github.com/web3/repo/pull/9"), "repo-pull-9");
	assert.equal(linkSlug("https://s3.example.com/k8/s3/DPS-19022"), "dps-19022");
	assert.equal(linkSlug("https://code.example.com/packages/Lib-2/reviews/CR-42"), "cr-42");
	assert.equal(linkSlug("https://example.com/%E0%A4%A"), undefined);
});

test("worker summaries read back the frontmatter", () => {
	const note = renderWorker({ ref, role: "orchestrator", session: "01a15dd2-70e3", cwd: "/r", pane: "w2:p1P", intercom: "abc", now });
	const fields = readFrontmatter(setFrontmatter(note, { status: "working" }));
	assert.equal(fields.pane, "w2:p1P");
	assert.equal(workerSummary(fields), "01a15dd2 orchestrator working pane w2:p1P intercom abc updated 2026-10-20T14:05");
	assert.deepEqual(readFrontmatter("no frontmatter"), {});
	assert.deepEqual(readFrontmatter('---\ntitle: "unterminated\nstatus: active\n---\n'), { title: '"unterminated', status: "active" });
});

test("sections parse, insert in order, and round trip", () => {
	const text = renderTask(ref, { title: "Fix sync", link: "https://x.example/A-1" }, now);
	const note = parseNote(text);
	assert.deepEqual(
		note.sections.map((section) => section.name),
		["Goal", "Status", "Next", "Log", "Workers"],
	);
	assert.equal(renderNote(note), text);
	const added = setSection(setSection(note, "Findings", "- f"), "Links", "- l");
	assert.deepEqual(
		added.sections.map((section) => section.name),
		["Goal", "Status", "Next", "Findings", "Links", "Log", "Workers"],
	);
	const custom = setSection(parseNote("# T\n\n## Mine\n\nkeep\n"), "Status", "s");
	assert.equal(renderNote(custom), "# T\n\n## Mine\n\nkeep\n\n## Status\n\ns\n");
	assert.equal(getSection(appendLines(added, "Workers", ["- w1", "- w2"]), "Workers"), "- w1\n- w2");
});

test("curator replies parse defensively", () => {
	const reply = `Sure:\n\`\`\`json\n{"status": "Two CRs posted.", "next": ["Merge CR-1", 3], "decisions": ["Split it"],
	"findings": [], "links": [{"url": "https://cr.example/1", "label": "CR 1"}, {"bad": 1}], "log": "posted\nboth",
	"state": "review", "win": {"title": "t", "impact": ""}}\n\`\`\``;
	const update = parseCuration(reply);
	assert.ok(update);
	assert.deepEqual(update.next, ["Merge CR-1"]);
	assert.deepEqual(update.links, [{ url: "https://cr.example/1", label: "CR 1" }]);
	assert.equal(update.log, "posted both");
	assert.equal(update.state, "review");
	assert.equal(update.win, undefined);
	assert.equal(parseCuration("no json here"), undefined);
	assert.equal(parseCuration('{"state": "done"}')?.state, undefined);
});

test("curation rewrites status and next, appends the rest", () => {
	const before = renderNote(
		appendLines(parseNote(renderTask(ref, { title: "Fix sync" }, now)), "Workers", ["- [01a15dd2](workers/01a15dd2.md) worker"]),
	);
	const once = applyCuration(
		before,
		{
			status: "Sync fixed locally.",
			next: ["Post CR"],
			decisions: ["Use flock"],
			findings: ["Activation PATH has no ssh (ogham.sh)"],
			links: [{ url: "https://cr.example/1", label: "CR 1" }],
			log: "fixed sync",
			win: { title: "Sync ships", summary: "", impact: "Notes reach the hub", evidence: [] },
		},
		now,
		"01a15dd2",
	);
	const twice = applyCuration(
		once,
		{ status: "CR posted.", next: [], decisions: [], findings: [], links: [{ url: "https://cr.example/1", label: "dup" }] },
		now,
		"01a15dd2",
	);
	const note = parseNote(twice);
	assert.equal(getSection(note, "Status"), "CR posted.");
	assert.equal(getSection(note, "Next"), "");
	assert.equal(getSection(note, "Decisions"), "- 2026-10-20 Use flock");
	assert.equal(getSection(note, "Links"), "- [CR 1](https://cr.example/1)");
	assert.equal(getSection(note, "Log"), "- 2026-10-20 14:05 01a15dd2 fixed sync\n- 2026-10-20 14:05 01a15dd2 win: Sync ships");
	assert.equal(note.sections.at(-1)?.name, "Workers");
	assert.equal(firstOpen(once), "Post CR");
});

test("urls, clipping, and zg hits", () => {
	const text = 'see https://cr.example/1, and (https://t.example/A-2). "https://cr.example/1"';
	assert.deepEqual(candidateUrls(text, ""), ["https://cr.example/1", "https://t.example/A-2"]);
	assert.deepEqual(candidateUrls(text, "https://cr.example/1"), ["https://t.example/A-2"]);
	const clipped = clip("a".repeat(100) + "z".repeat(100), 40);
	assert.ok(clipped.startsWith("a".repeat(10)) && clipped.endsWith("z".repeat(30)));
	assert.equal(clip("short", 40), "short");
	const output = `query groups (1):\nhits: 2\n\n#1 matchedBy=fts+vector topics/reset.md:8-11\nheading: 2026-10-20\nsource:\n8\t## 2026-10-20\n9\t\n10\t- NHS check runs before the wipe\n\n#2 matchedBy=vector topics/reset.md:2-3\nheading: type: topic\nsource:\n2\ttype: topic\n3\t---\n`;
	assert.deepEqual(parseHits(output), [
		{ file: "topics/reset.md", lines: "8-11", text: "## 2026-10-20\n\n- NHS check runs before the wipe" },
	]);
});

test("wins, topics, and the index", () => {
	const task = { title: "A-1: Fix sync", file: "projects/blizzard/a-1/a-1.md" };
	const win = renderWin({ title: "Sync ships", summary: "Notes sync.", impact: "No lost notes", evidence: ["https://cr.example/1"] }, now, task);
	assert.equal(
		win,
		"## 2026-10-20 Sync ships\n\nNotes sync.\n\n- Impact: No lost notes\n- Evidence: https://cr.example/1\n- Task: [A-1: Fix sync](projects/blizzard/a-1/a-1.md)\n",
	);
	const wins = `# Wins\n\n${win}\n## 2026-10-21 Other\n\n- Impact: x\n- Task: [B](projects/x/b/b.md)\n`;
	assert.equal(winsFor(wins, task.file), win.trim());
	assert.equal(winsFor(wins, "projects/none.md"), "");

	const topic = { slug: "sync", title: "Sync", summary: "How notes sync.", entries: ["flock guards runs"] };
	const created = appendTopic(undefined, topic, now, "[A-1](../projects/blizzard/a-1/a-1.md)");
	assert.equal(created, "---\ntype: topic\n---\n# Sync\n\nHow notes sync.\n\n## 2026-10-20\n\n- flock guards runs ([A-1](../projects/blizzard/a-1/a-1.md))\n");
	const same = appendTopic(created, { ...topic, entries: ["second"] }, now, "[A-1](x)");
	assert.match(same, /flock guards runs .*\n- second \(\[A-1\]\(x\)\)\n$/);
	const later = appendTopic(same, { ...topic, entries: ["third"] }, new Date(2026, 9, 22, 9, 0), "[A-1](x)");
	assert.match(later, /\n\n## 2026-10-22\n\n- third/);

	assert.deepEqual(parsePromotion('{"topics": [{"slug": "s", "title": "S", "entries": []}, {"slug": "t", "title": "T", "entries": ["e"]}]}'), {
		topics: [{ slug: "t", title: "T", summary: undefined, entries: ["e"] }],
		win: undefined,
	});

	const rows = [
		{ project: "b", file: "projects/b/x/x.md", title: "X [old]", status: "done", updated: "2026-10-19T10:00", next: "stale" },
		{ project: "b", file: "projects/b/y/y.md", title: "Y", status: "review", updated: "2026-10-20T10:00", next: "Merge" },
		{ project: "a", file: "projects/a/z/z.md", title: "Z", status: "active", updated: "2026-10-18T10:00" },
	];
	const index = renderIndex(rows, true);
	assert.equal(
		index,
		"# Tasks\n\n## a\n\n- [Z](projects/a/z/z.md) active, 2026-10-18T10:00\n\n## b\n\n- [Y](projects/b/y/y.md) review, 2026-10-20T10:00. Next: Merge\n\n## Done\n\n- [X \\[old\\]](projects/b/x/x.md) done, 2026-10-19T10:00\n\nWins: [wins.md](wins.md)\n",
	);
	assert.doesNotMatch(renderIndex(rows, false), /wins\.md/);
	assert.match(renderIndex(rows, false), /done, 2026-10-19T10:00\n$/);
});

test("transcripts drop ogham bookkeeping", () => {
	const messages = [
		{ role: "user", content: [{ type: "text", text: titlePrompt("https://t.example/A-1") }] },
		{ role: "assistant", content: [{ type: "text", text: "Binding." }, { type: "toolCall", name: "ogham_task" }] },
		{ role: "toolResult", toolName: "ogham_task", content: [{ type: "text", text: "Workers join with OGHAM_TASK=x" }] },
		{ role: "assistant", content: [{ type: "toolCall", name: "ogham_task" }] },
		{ role: "user", content: "fix the bug" },
		{ role: "assistant", content: [{ type: "toolCall", name: "bash" }] },
		{ role: "toolResult", toolName: "bash", content: [{ type: "text", text: "ok" }] },
	];
	assert.deepEqual(withoutBookkeeping(messages), [
		{ role: "assistant", content: [{ type: "text", text: "Binding." }] },
		messages[4],
		messages[5],
		messages[6],
	]);
});

test("locks serialize writers", async () => {
	const order: string[] = [];
	const slow = (name: string) =>
		withLock("ogham-test-lock", async () => {
			order.push(`${name}+`);
			await new Promise((resolve) => setTimeout(resolve, 30));
			order.push(`${name}-`);
		});
	await Promise.all([slow("a"), slow("b")]);
	assert.ok(order.join(",") === "a+,a-,b+,b-" || order.join(",") === "b+,b-,a+,a-", order.join(","));
});
