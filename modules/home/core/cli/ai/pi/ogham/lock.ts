// Cross-process lock via atomic mkdir.
import { createHash } from "node:crypto";
import { mkdir, rm, stat } from "node:fs/promises";
import { tmpdir, userInfo } from "node:os";
import * as path from "node:path";

const STALE_MS = 60_000;
const WAIT_MS = 15_000;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function withLock<T>(key: string, fn: () => Promise<T>): Promise<T> {
	// Outside the vault, so sync never commits it.
	const dir = path.join(tmpdir(), `ogham-locks-${userInfo().username}`);
	await mkdir(dir, { recursive: true });
	const lock = path.join(dir, createHash("sha1").update(key).digest("hex"));
	const deadline = Date.now() + WAIT_MS;
	for (;;) {
		try {
			await mkdir(lock);
			break;
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
			const age = Date.now() - ((await stat(lock).catch(() => undefined))?.mtimeMs ?? Date.now());
			if (age > STALE_MS) await rm(lock, { recursive: true, force: true });
			else if (Date.now() > deadline) throw new Error(`lock busy for ${key}`);
			else await sleep(50);
		}
	}
	try {
		return await fn();
	} finally {
		await rm(lock, { recursive: true, force: true });
	}
}
