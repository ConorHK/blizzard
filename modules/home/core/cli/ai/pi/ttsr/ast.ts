import { spawn } from "node:child_process";
import type { AstMatcher } from "./manager.ts";

const TIMEOUT_MS = 10_000;

function matchOnce(bin: string, pattern: string, source: string, lang: string): Promise<boolean> {
	return new Promise((resolve, reject) => {
		const child = spawn(bin, ["run", "--pattern", pattern, "--lang", lang, "--stdin", "--json=compact"], {
			stdio: ["pipe", "pipe", "pipe"],
		});
		let stderr = "";
		const timer = setTimeout(() => child.kill("SIGKILL"), TIMEOUT_MS);
		child.stdout.resume();
		child.stderr.on("data", chunk => {
			stderr += chunk;
		});
		child.on("error", error => {
			clearTimeout(timer);
			reject(error);
		});
		child.on("close", code => {
			clearTimeout(timer);
			// Exit 0: match; 1: none.
			if (code === 0) resolve(true);
			else if (code === 1) resolve(false);
			else reject(new Error(stderr.trim() || `ast-grep exited ${code}`));
		});
		child.stdin.on("error", () => {});
		child.stdin.end(source);
	});
}

export function astGrepMatcher(bin: string): AstMatcher {
	return async (patterns, source, lang) => {
		for (const pattern of patterns) {
			if (await matchOnce(bin, pattern, source, lang)) return true;
		}
		return false;
	};
}
