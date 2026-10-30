import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import * as path from "node:path";
import { test } from "node:test";
import {
	findUrl,
	linkSlug,
	parseRef,
	projectFor,
	readFrontmatter,
	readList,
	refFromNote,
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
	scrubUrl,
	taskChoices,
	withoutBookkeeping,
} from "./ogham/curate.ts";
import {
	addDays,
	addMeasured,
	artifactCounts,
	artifactsOf,
	closeDue,
	impactDue,
	legacyWins,
	mergeArtifacts,
	noArtifacts,
	parseMeasure,
	parseWinFile,
	renderWinFile,
	renderWinsIndex,
	winFile,
	winsFor,
} from "./ogham/wins.ts";
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
	"findings": [], "links": [{"url": "https://cr.example/1", "label": "CR 1"}, {"bad": 1}, {"url": "https://evil.example/x"}], "log": "posted\nboth",
	"state": "review", "win": {"title": "t", "impact": ""}}\n\`\`\``;
	const update = parseCuration(reply, ["https://cr.example/1"]);
	assert.ok(update);
	assert.deepEqual(update.next, ["Merge CR-1"]);
	assert.deepEqual(update.links, [{ url: "https://cr.example/1", label: "CR 1" }]);
	assert.equal(update.log, "posted both");
	assert.equal(update.state, "review");
	assert.equal(update.win, undefined);
	assert.equal(parseCuration("no json here", []), undefined);
	assert.equal(parseCuration('{"state": "finished"}', [])?.state, undefined);

	const signed = "https://bucket.example/log.txt?X-Amz-Signature=abc&X-Amz-Credential=def";
	const scrubbed = parseCuration(
		`{"findings": ["Log at ${signed}"], "links": [{"url": "${signed}", "label": "log"}]}`,
		candidateUrls(`fetched ${signed}`, ""),
	);
	assert.deepEqual(scrubbed?.findings, ["Log at https://bucket.example/log.txt"]);
	assert.deepEqual(scrubbed?.links, [{ url: "https://bucket.example/log.txt", label: "log" }]);
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
		{
			status: "CR posted.",
			next: [],
			decisions: [],
			findings: [],
			links: [
				{ url: "https://cr.example/1", label: "dup" },
				{ url: "https://cr.example/2", label: "CR [2]" },
			],
		},
		now,
		"01a15dd2",
	);
	const note = parseNote(twice);
	assert.equal(getSection(note, "Status"), "CR posted.");
	assert.equal(getSection(note, "Next"), "");
	assert.equal(getSection(note, "Decisions"), "- 2026-10-20 Use flock");
	assert.equal(getSection(note, "Links"), "- [CR 1](https://cr.example/1)\n- [CR \\[2\\]](https://cr.example/2)");
	assert.equal(getSection(note, "Log"), "- 2026-10-20 14:05 01a15dd2 fixed sync\n- 2026-10-20 14:05 01a15dd2 win: Sync ships");
	assert.equal(note.sections.at(-1)?.name, "Workers");
	assert.equal(firstOpen(once), "Post CR");
});

test("urls, clipping, and zg hits", () => {
	const text = 'see https://cr.example/1, and (https://t.example/A-2). "https://cr.example/1"';
	assert.deepEqual(candidateUrls(text, ""), ["https://cr.example/1", "https://t.example/A-2"]);
	assert.deepEqual(candidateUrls(text, "https://cr.example/1"), ["https://t.example/A-2"]);
	assert.equal(scrubUrl("https://a.example/cb#access_token=t&state=s"), "https://a.example/cb");
	assert.equal(scrubUrl("https://a.example/p?api_key=k"), "https://a.example/p");
	assert.equal(scrubUrl("https://a.example/p?region=us-east-1#logsV2:log-groups"), "https://a.example/p?region=us-east-1#logsV2:log-groups");
	const clipped = clip("a".repeat(100) + "z".repeat(100), 40);
	assert.ok(clipped.startsWith("a".repeat(10)) && clipped.endsWith("z".repeat(30)));
	assert.equal(clip("short", 40), "short");
	const output = `query groups (1):\nhits: 2\n\n#1 matchedBy=fts+vector topics/reset.md:8-11\nheading: 2026-10-20\nsource:\n8\t## 2026-10-20\n9\t\n10\t- NHS check runs before the wipe\n\n#2 matchedBy=vector topics/reset.md:2-3\nheading: type: topic\nsource:\n2\ttype: topic\n3\t---\n`;
	assert.deepEqual(parseHits(output), [
		{ file: "topics/reset.md", lines: "8-11", text: "## 2026-10-20\n\n- NHS check runs before the wipe" },
	]);
});

test("wins, topics, and the index", () => {
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

	const twin = { project: "a", file: "projects/a/z2/z2.md", title: "Z", status: "blocked", updated: "2026-10-17T10:00" };
	assert.deepEqual(taskChoices([...rows, twin], 3), [
		{ label: "b: Y", ref: "b/y" },
		{ label: "a: Z", ref: "a/z" },
		{ label: "a: Z (a/z2)", ref: "a/z2" },
	]);
	assert.equal(taskChoices(rows, 1).length, 1);
	const long = taskChoices([{ ...twin, title: "t".repeat(80) }], 7)[0].label;
	assert.equal(long, `a: ${"t".repeat(69)}...`);
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
	assert.equal(statSync(path.join(homedir(), ".cache", "ogham-locks")).mode & 0o777, 0o700);
});

test("curator reports initiative, done, and win fields", () => {
	const reply = `{"state": "done", "initiative": "DPS-18081: NDDS  pipeline health", "win": {"title": "RUH restored", "impact": "3 hosts serve",
	"category": "Reliability", "role": "boss", "metric": "canary failures per 5 min", "before": "20", "after": "0", "scope": "EC2 RUH"}}`;
	const update = parseCuration(reply, []);
	assert.equal(update?.state, "done");
	assert.equal(update?.initiative, "DPS-18081: NDDS pipeline health");
	assert.deepEqual(update?.win, {
		title: "RUH restored",
		summary: "",
		impact: "3 hosts serve",
		evidence: [],
		category: "reliability",
		role: undefined,
		metric: "canary failures per 5 min",
		before: "20",
		after: "0",
		scope: "EC2 RUH",
	});
	assert.equal(parseCuration('{"initiative": "  "}', [])?.initiative, undefined);
});

test("win files round trip and list by initiative", () => {
	const file = winFile("2026-10-30", "RUH: restored [3/3]");
	assert.equal(file, "wins/2026-10-30-ruh-restored-3-3.md");
	assert.equal(winFile("2026-10-30", "RUH", 2), "wins/2026-10-30-ruh-2.md");
	const record = {
		file,
		date: "2026-10-30",
		title: "RUH: restored [3/3]",
		summary: "Replacement host serves.",
		impact: "Clears the pipeline blocker",
		evidence: ["https://t.example/V1", "https://p.example/2"],
		task: "projects/ndds/dps-1/dps-1.md",
		initiative: "DPS-9: Pipeline health",
		category: "reliability" as const,
		role: "led" as const,
		metric: "canary failures per 5 min",
		before: "20",
		after: "0",
		scope: "",
		artifacts: { ...noArtifacts(), tickets: ["https://t.example/V1"], code: ["https://code.amazon.com/reviews/CR-1", "https://code.amazon.com/reviews/CR-2"] },
	};
	const text = renderWinFile(record, "DPS-1: [NDDS] Unblock");
	assert.match(text, /^---\ntype: win\ndate: 2026-10-30\ntask: projects\/ndds\/dps-1\/dps-1\.md\ninitiative: "DPS-9: Pipeline health"\n/);
	assert.doesNotMatch(text, /scope:|sims:|docs:/);
	assert.match(text, /\ntickets: \["https:\/\/t\.example\/V1"\]\ncode: \["https:\/\/code\.amazon\.com\/reviews\/CR-1","https:\/\/code\.amazon\.com\/reviews\/CR-2"\]\n---\n/);
	assert.match(text, /\n- Task: \[DPS-1: \\\[NDDS\\\] Unblock\]\(\.\.\/projects\/ndds\/dps-1\/dps-1\.md\)\n$/);
	assert.deepEqual(parseWinFile(file, text), { ...record, scope: undefined, measured: undefined, result: undefined, impactAfter: undefined });
	assert.equal(parseWinFile("wins/x.md", "---\ntype: task\n---\n# X\n"), undefined);

	const measured = parseWinFile(file, addMeasured(setFrontmatter(text, { measured: "2026-11-14", result: "pages: 5 -> 1" }), "2026-11-14", "pages: 5 -> 1"));
	assert.equal(measured?.measured, "2026-11-14");
	assert.equal(measured?.impact, "Clears the pipeline blocker");

	const other = { ...record, file: "wins/2026-09-01-a.md", date: "2026-09-01", title: "A", initiative: undefined, category: undefined, role: undefined, metric: undefined, after: undefined, result: "faster", artifacts: noArtifacts() };
	const newer = { ...record, file: "wins/2026-11-01-b.md", date: "2026-11-01", title: "B", metric: undefined, after: undefined };
	assert.equal(
		renderWinsIndex([other, record, newer]),
		[
			"# Wins",
			"",
			"<!-- ogham builds this from wins/; edits here are lost. -->",
			"",
			"## DPS-9: Pipeline health",
			"",
			"- 2026-11-01 [B](wins/2026-11-01-b.md): reliability, led. Clears the pipeline blocker (1 ticket, 2 code changes)",
			"- 2026-10-30 [RUH: restored \\[3/3\\]](wins/2026-10-30-ruh-restored-3-3.md): reliability, led. canary failures per 5 min: 20 -> 0 (1 ticket, 2 code changes)",
			"",
			"## No initiative",
			"",
			"- 2026-09-01 [A](wins/2026-09-01-a.md): faster",
			"",
		].join("\n"),
	);
	assert.equal(winsFor([other, record], record.task), "- 2026-09-01 A: Clears the pipeline blocker\n- 2026-10-30 RUH: restored [3/3]: Clears the pipeline blocker");
	assert.equal(winsFor([record], "projects/none.md"), "");
});

test("old wins.md entries migrate", () => {
	const old = [
		"# Wins",
		"",
		"## 2026-10-30 EC2-RUH ruh60 slot restored",
		"",
		"Replacement host serves.",
		"",
		"- Impact: Restores RUH capacity to 3 hosts.",
		"- Evidence: https://t.example/V2396853391, https://a.example/1145519297904",
		"- Task: [DPS-19023: \\[NDDS\\] Unblock pipeline](projects/networkdevicediscoveryservice/dps-19023/dps-19023.md)",
		"",
		"## No initiative",
		"",
		"- 2026-09-01 [A](wins/2026-09-01-a.md): faster",
		"",
	].join("\n");
	assert.deepEqual(legacyWins(old), [
		{
			file: "wins/2026-10-30-ec2-ruh-ruh60-slot-restored.md",
			date: "2026-10-30",
			title: "EC2-RUH ruh60 slot restored",
			summary: "Replacement host serves.",
			impact: "Restores RUH capacity to 3 hosts.",
			evidence: ["https://t.example/V2396853391", "https://a.example/1145519297904"],
			task: "projects/networkdevicediscoveryservice/dps-19023/dps-19023.md",
			artifacts: noArtifacts(),
		},
	]);
	assert.deepEqual(legacyWins(renderWinsIndex([])), []);
});

test("measures, days, and note paths", () => {
	assert.deepEqual(parseMeasure(" time to deploy: 3 h -> 40 min "), { metric: "time to deploy", before: "3 h", after: "40 min" });
	assert.equal(parseMeasure("about half the pages"), undefined);
	assert.equal(addDays("2026-10-30", 14), "2026-11-13");
	assert.equal(addDays("2026-12-25", 7), "2027-01-01");
	assert.deepEqual(refFromNote("projects/blizzard/dps-1/dps-1.md"), { project: "blizzard", slug: "dps-1" });
	assert.equal(refFromNote("projects/blizzard/dps-1/workers/x.md"), undefined);
});

test("follow-ups ask for impact and closing", () => {
	const today = "2026-11-20";
	const task = (slug: string, status: string, updated: string, more = {}) => ({
		project: "p",
		file: `projects/p/${slug}/${slug}.md`,
		title: slug.toUpperCase(),
		status,
		updated,
		...more,
	});
	const win = (name: string, date: string, more = {}) => ({ file: `wins/${name}.md`, date, title: name, summary: "", impact: "i", evidence: [], ...more });
	const wins = [
		win("old", "2026-10-30", { task: "projects/p/a/a.md" }),
		win("fresh", "2026-11-10"),
		win("measured", "2026-10-01", { measured: "2026-10-20" }),
		win("numbers", "2026-10-01", { metric: "m", after: "1" }),
		win("snoozed", "2026-10-01", { impactAfter: "2026-11-25" }),
		win("never", "2026-10-01", { impactAfter: "never" }),
		win("woke", "2026-10-02", { impactAfter: "2026-11-20" }),
	];
	const tasks = [
		task("a", "done", "2026-10-30T10:00", { closed: "2026-10-30T10:00" }),
		task("b", "review", "2026-11-01T10:00"),
		task("c", "done", "2026-11-15T10:00", { closed: "2026-11-15T10:00" }),
		task("d", "active", "2026-10-01T10:00"),
		task("e", "active", "2026-11-19T10:00", { resolved: "2026-11-19" }),
		task("f", "active", "2026-10-01T10:00", { closeAfter: "2026-12-01" }),
		task("g", "blocked", "2026-11-18T10:00"),
	];
	assert.deepEqual(
		impactDue(wins, tasks, today, 5).map((item) => [item.kind, item.label]),
		[
			["impact-win", "Impact: woke"],
			["impact-win", "Impact: old"],
			["impact-task", "Impact: p: B"],
		],
	);
	assert.equal(impactDue(wins, tasks, today, 1).length, 1);
	assert.deepEqual(
		closeDue(tasks, today, 5).map((item) => [item.kind, item.label, item.file]),
		[
			["close", "Close: p: E", "projects/p/e/e.md"],
			["close", "Close: p: D", "projects/p/d/d.md"],
		],
	);
});

test("artifacts sort URLs into tickets, SIMs, code, and docs", () => {
	const found = artifactsOf([
		"https://code.amazon.com/reviews/CR-315504661/revisions/1#/diff",
		"https://code.amazon.com/reviews/CR-315504661",
		"https://code.amazon.com/packages/NetworkDeviceDiscoveryServiceCDK/commits/0a09f57660f287d4a837e8ccba14155736b82dc7",
		"https://code.amazon.com/packages/DCFNSTNOCDK/blobs/8cb43fa1cb8d01c4799478772abf30b9422fa39e",
		"https://github.com/ConorHK/blizzard/pull/42/files",
		"https://t.corp.amazon.com/V2396853391/communication",
		"https://t.corp.amazon.com/P543719309.",
		"https://mcm.amazon.com/cms/MCM-123456",
		"https://taskei.amazon.dev/tasks/DPS-19023",
		"https://sim.amazon.com/issues/DPS-19023",
		"https://sim.amazon.com/issues/DPS-19022",
		"https://w.amazon.com/bin/view/AWSRegionBuilds/RBX/RegionBuildAutomationBlockers/#HWhatconstitutes",
		"https://chorus.aws.dev/doc/abc123/Design",
		"https://pipelines.amazon.com/pipelines/NetworkDeviceDiscoveryService",
		"https://tiny.amazon.com/fas2zu17",
	]);
	assert.deepEqual(found, {
		tickets: ["https://t.corp.amazon.com/V2396853391", "https://t.corp.amazon.com/P543719309", "https://mcm.amazon.com/cms/MCM-123456"],
		sims: ["https://taskei.amazon.dev/tasks/DPS-19023", "https://sim.amazon.com/issues/DPS-19022"],
		code: [
			"https://code.amazon.com/reviews/CR-315504661",
			"https://code.amazon.com/packages/NetworkDeviceDiscoveryServiceCDK/commits/0a09f57660f287d4a837e8ccba14155736b82dc7",
			"https://github.com/ConorHK/blizzard/pull/42",
		],
		docs: ["https://w.amazon.com/bin/view/AWSRegionBuilds/RBX/RegionBuildAutomationBlockers/", "https://chorus.aws.dev/doc/abc123/Design"],
	});
	const merged = mergeArtifacts({ ...noArtifacts(), code: ["https://code.amazon.com/reviews/CR-1"] }, artifactsOf(["https://code.amazon.com/reviews/CR-1/revisions/2", "https://t.corp.amazon.com/V9"]));
	assert.deepEqual(merged, { ...noArtifacts(), tickets: ["https://t.corp.amazon.com/V9"], code: ["https://code.amazon.com/reviews/CR-1"] });
	assert.equal(artifactCounts(found), "3 tickets, 2 SIMs, 3 code changes, 2 docs");
	assert.equal(artifactCounts(noArtifacts()), "");
	assert.equal(yamlValue(["a", "b c"]), '["a","b c"]');
	assert.deepEqual(readList('["a","b c"]'), ["a", "b c"]);
	assert.deepEqual(readList("[broken"), []);
	assert.deepEqual(readList(undefined), []);
});
