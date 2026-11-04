// Names each pi session after its herdr space and tab, with its ogham task's id once one is bound.
import { type ChildProcess, spawn } from "node:child_process";
import type { Socket } from "node:net";
import { createInterface } from "node:readline";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const ENTRY = "herdr-name";
const RETRY_MS = 5_000;

interface TaskEvent {
	slug: string | null;
}

interface Given {
	name: string;
}

// herdr-app labels its terminals with where="<space> / <tab>".
function whereOf(labels: unknown): string | undefined {
	const where = (labels as Record<string, unknown> | undefined)?.where;
	return typeof where === "string" && where.includes(" / ") ? where : undefined;
}

export default function herdrName(pi: ExtensionAPI) {
	const terminal = process.env.HC_TERMINAL_ID;
	if (!terminal) return;
	let where: string | undefined;
	let slug: string | null = null;
	// The name this extension gave last; any other name is the user's and stays.
	let given: string | undefined;
	let events: ChildProcess | undefined;
	let closing = false;

	function apply(): void {
		if (!where) return;
		const current = pi.getSessionName();
		if (current && current !== given) return;
		const cut = where.indexOf(" / ");
		const name = [where.slice(0, cut), where.slice(cut + 3), ...(slug ? [slug] : [])].join("-");
		if (name === current) return;
		try {
			pi.setSessionName(name);
			given = name;
			pi.appendEntry<Given>(ENTRY, { name });
		} catch {
			// Between sessions there is none to name; the next session_start names it.
		}
	}

	function seen(labels: unknown): void {
		const next = whereOf(labels);
		if (!next || next === where) return;
		where = next;
		apply();
	}

	async function read(): Promise<void> {
		const r = await pi.exec("hc", ["get", terminal, "--json"], { timeout: 5_000 }).catch(() => undefined);
		if (r?.code !== 0) return;
		try {
			seen(JSON.parse(r.stdout)?.labels);
		} catch {
			// A half-written answer; the next run asks again.
		}
	}

	// Moving the terminal to another tab or space relabels it, so follow its label changes.
	function follow(): void {
		if (events || closing) return;
		const child = spawn("hc", ["events", "--terminal", terminal, "--json"], { stdio: ["ignore", "pipe", "ignore"] });
		events = child;
		// The stream must not keep pi alive, nor outlive it.
		child.unref();
		(child.stdout as Socket).unref();
		const stop = () => child.kill();
		process.once("exit", stop);
		createInterface({ input: child.stdout }).on("line", (line) => {
			try {
				const event = JSON.parse(line);
				if (event.terminals) seen(event.terminals.find((t: { address?: string }) => t.address === terminal)?.labels);
				else if (event.params?.type === "labels") seen(event.params.data?.labels);
			} catch {
				// Not JSON; hc only writes JSON lines with --json.
			}
		});
		const restart = () => {
			process.off("exit", stop);
			if (events !== child) return;
			events = undefined;
			if (!closing) setTimeout(follow, RETRY_MS).unref();
		};
		child.on("error", restart);
		child.on("exit", restart);
	}

	pi.events.on("ogham:task", (data) => {
		slug = (data as TaskEvent).slug;
		apply();
	});

	pi.on("session_start", async (_event, ctx: ExtensionContext) => {
		closing = false;
		given = undefined;
		const branch = ctx.sessionManager.getBranch();
		for (let i = branch.length - 1; i >= 0; i--) {
			const entry = branch[i];
			if (entry.type !== "custom" || entry.customType !== ENTRY) continue;
			given = (entry.data as Given | undefined)?.name;
			break;
		}
		apply();
		follow();
		void read();
	});

	// Covers a lost event stream.
	pi.on("agent_start", async () => {
		await read();
	});

	pi.on("session_shutdown", async () => {
		closing = true;
		events?.kill();
	});
}
