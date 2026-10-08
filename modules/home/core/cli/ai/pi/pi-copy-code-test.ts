import assert from "node:assert/strict";
import { test } from "node:test";
import { extractSnippets, snippetLabel, splitCommands } from "./copy-code/snippets.ts";

const longPath =
	"/workplace/knoconor/NetworkDeviceDiscoveryServiceControlPlane/src/NetworkDeviceDiscoveryServiceControlPlaneConfigGenerator";

const texts = (markdown: string) => extractSnippets(markdown).map((snippet) => snippet.text);
const commands = (block: string) => splitCommands(block).map((command) => command.text);

test("keeps long commands on one line", () => {
	const reply = `Run this:\n\n\`\`\`bash\ncd ${longPath}\n\`\`\``;
	assert.deepEqual(texts(reply), [`cd ${longPath}`]);
});

test("lists a block, its commands, then inline code", () => {
	const reply = "Edit `src/a.ts`, then:\n\n```\nnpm test\nnpm run lint\n```";
	assert.deepEqual(extractSnippets(reply), [
		{ text: "npm test\nnpm run lint", context: "whole block" },
		{ text: "npm test", context: undefined, nested: true },
		{ text: "npm run lint", context: undefined, nested: true },
		{ text: "src/a.ts" },
	]);
});

test("splits commented groups and keeps comments as context", () => {
	const block = [
		"# CR 1: revise CR-311369476",
		"cr -r CR-311369476 --from mlwkpyqn --to yvqxulqp --destination-branch mainline",
		"",
		"# CR 2: regional health alarms",
		"cr --from yvqxulqp --to smxrqtvk --destination-branch mainline",
	].join("\n");
	assert.deepEqual(splitCommands(block), [
		{
			text: "cr -r CR-311369476 --from mlwkpyqn --to yvqxulqp --destination-branch mainline",
			context: "CR 1: revise CR-311369476",
			nested: true,
		},
		{
			text: "cr --from yvqxulqp --to smxrqtvk --destination-branch mainline",
			context: "CR 2: regional health alarms",
			nested: true,
		},
	]);
});

test("offers the command when a comment precedes it", () => {
	assert.deepEqual(texts("```\n# go there\ncd /tmp\n```"), ["# go there\ncd /tmp", "cd /tmp"]);
});

test("joins continued lines", () => {
	assert.deepEqual(commands("aws s3 cp \\\n  a b\nls |\n  wc -l\nmake &&\n  make install"), [
		"aws s3 cp \\\n  a b",
		"ls |\n  wc -l",
		"make &&\n  make install",
	]);
});

test("keeps heredocs, quotes and brackets whole", () => {
	assert.deepEqual(commands("cat <<'EOF' > x\nhi\n\nEOF\necho done"), ["cat <<'EOF' > x\nhi\n\nEOF", "echo done"]);
	assert.deepEqual(commands("cat <<-EOF\n\tbody\n\tEOF\nls"), ["cat <<-EOF\n\tbody\n\tEOF", "ls"]);
	assert.deepEqual(commands("git commit -m 'one\n\ntwo'\ngit log"), ["git commit -m 'one\n\ntwo'", "git log"]);
	assert.deepEqual(commands("f() {\n  ls\n}\nf"), ["f() {\n  ls\n}", "f"]);
	assert.deepEqual(commands("cat <<< \"$x\"\nls"), ['cat <<< "$x"', "ls"]);
});

test("ignores quotes inside comments", () => {
	assert.deepEqual(commands("make # don't\nls"), ["make # don't", "ls"]);
});

test("does not split non-shell blocks", () => {
	assert.deepEqual(texts("```nix\na = 1;\nb = 2;\n```"), ["a = 1;\nb = 2;"]);
	assert.deepEqual(texts('```\n{\n  "a": 1\n}\n```'), ['{\n  "a": 1\n}']);
});

test("dedents blocks inside list items", () => {
	const reply = "1. Build\n   ```sh\n   make \\\n     -j4\n   ```";
	assert.deepEqual(texts(reply), ["make \\\n  -j4"]);
});

test("needs a closing fence at least as long", () => {
	assert.deepEqual(texts("````md\n```\ninner\n```\n````"), ["```\ninner\n```"]);
});

test("keeps an unclosed trailing block", () => {
	assert.deepEqual(texts("```\nstreaming"), ["streaming"]);
});

test("drops duplicates and blanks", () => {
	assert.deepEqual(texts("`x` and `x` and ` `"), ["x"]);
});

test("labels context, nesting and length", () => {
	assert.equal(snippetLabel({ text: "a\nb\nc" }, 1), "2. a (+2 lines)");
	assert.equal(snippetLabel({ text: "ls", context: "list", nested: true }, 2), "  3. list | ls");
	const label = snippetLabel({ text: `cd ${longPath}` }, 0);
	assert.ok(label.endsWith("..."));
	assert.ok(label.length <= 75);
});

test("shortens long comment labels", () => {
	const label = snippetLabel({ text: `cd ${longPath}`, context: "x".repeat(80), nested: true }, 0);
	assert.ok(label.length <= 77, `${label.length}: ${label}`);
	assert.match(label, /\.\.\. \| cd \/workplace/);
});
