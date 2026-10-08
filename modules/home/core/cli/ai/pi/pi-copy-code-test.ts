import assert from "node:assert/strict";
import { test } from "node:test";
import { extractSnippets, snippetLabel } from "./copy-code/snippets.ts";

const longPath =
	"/workplace/knoconor/NetworkDeviceDiscoveryServiceControlPlane/src/NetworkDeviceDiscoveryServiceControlPlaneConfigGenerator";

test("keeps long commands on one line", () => {
	const reply = `Run this:\n\n\`\`\`bash\ncd ${longPath}\n\`\`\``;
	assert.deepEqual(extractSnippets(reply), [`cd ${longPath}`]);
});

test("puts fenced blocks before inline code", () => {
	const reply = "Edit `src/a.ts`, then:\n\n```\nnpm test\nnpm run lint\n```";
	assert.deepEqual(extractSnippets(reply), ["npm test\nnpm run lint", "src/a.ts"]);
});

test("dedents blocks inside list items", () => {
	const reply = "1. Build\n   ```sh\n   make\n     indented\n   ```";
	assert.deepEqual(extractSnippets(reply), ["make\n  indented"]);
});

test("needs a closing fence at least as long", () => {
	const reply = "````md\n```\ninner\n```\n````";
	assert.deepEqual(extractSnippets(reply), ["```\ninner\n```"]);
});

test("keeps an unclosed trailing block", () => {
	assert.deepEqual(extractSnippets("```\nstreaming"), ["streaming"]);
});

test("drops duplicates and blanks", () => {
	assert.deepEqual(extractSnippets("`x` and `x` and ` `"), ["x"]);
});

test("labels long and multi-line snippets", () => {
	assert.equal(snippetLabel("a\nb\nc", 1), "2. a (+2 lines)");
	const label = snippetLabel(`cd ${longPath}`, 0);
	assert.ok(label.endsWith("..."));
	assert.ok(label.length <= 75);
});
