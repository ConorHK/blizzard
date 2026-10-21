// Semantic search over the vault with zg.
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);
const EMBEDDING = "local/potion-retrieval-32m";

export interface Hit {
	file: string;
	lines: string;
	text: string;
}

export function parseHits(output: string): Hit[] {
	const hits: Hit[] = [];
	for (const chunk of output.split(/^#\d+ matchedBy=\S+ /m).slice(1)) {
		const location = /^(\S+):(\d+(?:-\d+)?)/.exec(chunk);
		const source = chunk.split(/^source:\n/m)[1];
		if (!location || source === undefined) continue;
		const text = source
			.split("\n")
			.map((line) => line.replace(/^\d+\t/, ""))
			.join("\n")
			.trim();
		// Frontmatter-only chunks carry nothing.
		const content = text.replace(/^(---|[\w-]+: .*)$/gm, "").trim();
		if (content.length >= 20) hits.push({ file: location[1], lines: location[2], text });
	}
	return hits;
}

export async function reindex(zg: string, vault: string): Promise<void> {
	await run(zg, ["index", vault, "--embedding", EMBEDDING, "--mode", "direct"], { cwd: vault, timeout: 300_000 });
}

export async function search(zg: string, vault: string, query: string, exclude: string, limit: number): Promise<Hit[]> {
	const args = ["query", query, "--mode", "direct", "--limit", String(limit), "--preview", "full"];
	args.push("--refresh", "wait", "-g", `!${exclude}/**`, "-g", "!index.md");
	const { stdout } = await run(zg, args, { cwd: vault, timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
	return parseHits(stdout);
}
