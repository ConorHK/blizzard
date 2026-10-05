// Ported from oh-my-pi (MIT): advisor/watchdog.ts discovery.
import { existsSync, readFileSync } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface ContextFile {
	path: string;
	content: string;
}

function read(file: string): ContextFile | undefined {
	try {
		return existsSync(file) ? { path: file, content: readFileSync(file, "utf8").trim() } : undefined;
	} catch {
		return undefined;
	}
}

/** From cwd up to repo root. */
function ancestors(cwd: string): string[] {
	const dirs: string[] = [];
	const home = os.homedir();
	let dir = path.resolve(cwd);
	for (;;) {
		dirs.push(dir);
		if (existsSync(path.join(dir, ".git")) || existsSync(path.join(dir, ".jj")) || dir === home) break;
		const parent = path.dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return dirs.reverse();
}

/** Standing instructions, as pi loads them. */
export function contextFiles(cwd: string, agentDir: string, trusted: boolean): ContextFile[] {
	const files: ContextFile[] = [];
	const global = read(path.join(agentDir, "AGENTS.md"));
	if (global) files.push(global);
	if (!trusted) return files;
	for (const dir of ancestors(cwd)) {
		const file = read(path.join(dir, "AGENTS.md")) ?? read(path.join(dir, "CLAUDE.md"));
		if (file) files.push(file);
	}
	return files;
}

/** Advisor-only guidance; nearer files come last. */
export function watchdogFiles(cwd: string, agentDir: string, trusted: boolean): ContextFile[] {
	const files: ContextFile[] = [];
	const user = read(path.join(agentDir, "WATCHDOG.md"));
	if (user) files.push(user);
	if (!trusted) return files;
	for (const dir of ancestors(cwd)) {
		for (const candidate of [path.join(dir, "WATCHDOG.md"), path.join(dir, ".pi", "WATCHDOG.md")]) {
			const file = read(candidate);
			if (file) files.push(file);
		}
	}
	return files;
}
