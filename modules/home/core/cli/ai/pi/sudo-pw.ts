// sudo over ssh; the password stays out of context.
import { spawn } from "node:child_process";
import type { ExtensionAPI, ExtensionUIContext, Theme } from "@earendil-works/pi-coding-agent";
import {
	CURSOR_MARKER,
	Text,
	truncateToWidth,
	wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";

interface SudoDetails {
	host: string;
	exitCode: number | null;
	authFailure: boolean;
}

interface RunResult {
	code: number | null;
	output: string;
	timedOut: boolean;
}

// Passwords live here only; never in messages.
const cache = new Map<string, string>();

const Params = Type.Object({
	host: Type.String({ description: "ssh destination, e.g. leprechaun" }),
	command: Type.String({ description: "shell command run under sudo on the host" }),
	user: Type.Optional(Type.String({ description: "run as this user instead of root" })),
	timeoutSec: Type.Optional(Type.Number({ description: "kill after N seconds, default 120" })),
});

function shQuote(text: string): string {
	return `'${text.replaceAll("'", "'\\''")}'`;
}

function sudoWrap(command: string, user?: string): string {
	const flag = user ? ` -u ${shQuote(user)}` : "";
	return `sudo -S -p ''${flag} -- bash -c ${shQuote(command)}`;
}

function scrub(text: string, secret: string | undefined): string {
	if (!secret) return text;
	return text.split(secret).join("********");
}

function runSsh(
	host: string,
	remote: string,
	password: string | undefined,
	signal: AbortSignal | undefined,
	timeoutMs: number,
): Promise<RunResult> {
	return new Promise((resolve) => {
		const child = spawn("ssh", ["-o", "ConnectTimeout=10", host, remote], {
			stdio: ["pipe", "pipe", "pipe"],
		});
		let output = "";
		let timedOut = false;
		const timer = setTimeout(() => {
			timedOut = true;
			child.kill("SIGKILL");
		}, timeoutMs);
		const onAbort = () => child.kill("SIGKILL");
		signal?.addEventListener("abort", onAbort, { once: true });
		const take = (chunk: Buffer) => {
			if (output.length < 1_000_000) output += chunk.toString();
		};
		child.stdout.on("data", take);
		child.stderr.on("data", take);
		child.on("error", (err) => (output += `ssh failed: ${err.message}`));
		child.stdin.on("error", () => {});
		if (password !== undefined) child.stdin.write(`${password}\n`);
		child.stdin.end();
		child.on("close", (code) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", onAbort);
			resolve({ code, output, timedOut });
		});
	});
}

async function askPassword(
	ctx: { mode: string; ui: ExtensionUIContext },
	host: string,
	command: string,
): Promise<string | null> {
	if (ctx.mode !== "tui") return null;
	return ctx.ui.custom<string | null>((tui, theme, _kb, done) => {
		let chars: string[] = [];

		function handleInput(data: string) {
			if (data === "\r" || data === "\n") {
				done(chars.join(""));
				return;
			}
			if (data === "\x1b" || data === "\x03") {
				done(null);
				return;
			}
			if (data === "\x7f" || data === "\b") {
				chars.pop();
				tui.requestRender();
				return;
			}
			if (data === "\x15") {
				chars = [];
				tui.requestRender();
				return;
			}
			if (data.includes("\x1b")) return;
			for (const ch of data.replace(/[\r\n]/g, "")) {
				const code = ch.charCodeAt(0);
				if (code >= 32 && code !== 127) chars.push(ch);
			}
			tui.requestRender();
		}

		function render(width: number): string[] {
			const lines: string[] = [];
			const title = theme.fg("accent", `sudo password: ${host}`);
			lines.push(...wrapTextWithAnsi(title, width));
			lines.push("");
			const preview = truncateToWidth(`runs: ${command}`, Math.max(1, width - 2), "...");
			lines.push(...wrapTextWithAnsi(theme.fg("muted", preview), width));
			lines.push("");
			const shown = "*".repeat(Math.min(chars.length, Math.max(0, width - 12)));
			lines.push(`password: ${shown}${CURSOR_MARKER}\x1b[7m \x1b[27m`);
			lines.push("");
			lines.push(theme.fg("dim", "Enter submits, Esc cancels"));
			return lines;
		}

		return { focused: true, invalidate: () => {}, handleInput, render };
	});
}

function fail(host: string, text: string) {
	return {
		content: [{ type: "text" as const, text }],
		details: { host, exitCode: null, authFailure: false } as SudoDetails,
		isError: true,
	};
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "sudo_ssh",
		label: "Sudo ssh",
		description:
			"Run a command as root on a remote host over ssh. The user types the sudo password into a hidden dialog; the password never enters the conversation. It is cached per host for the session; later calls show a confirmation. A wrong password clears the cache so the next call re-prompts.",
		parameters: Params,
		annotations: { destructiveHint: true, openWorldHint: true },
		promptSnippet: "Run commands as root on remote hosts via a hidden sudo password prompt.",
		promptGuidelines: [
			"Use sudo_ssh for privileged commands on remote hosts.",
			"Never ask the user to type a password into chat.",
		],
		async execute(_id, params, signal, _onUpdate, ctx) {
			if (ctx.mode !== "tui") {
				return fail(params.host, "sudo_ssh needs the interactive UI.");
			}
			const host = params.host;
			const timeoutMs = Math.max(1, params.timeoutSec ?? 120) * 1000;

			// Probe first: only feed stdin when sudo will ask.
			const probe = await runSsh(host, "sudo -n true", undefined, signal, Math.min(timeoutMs, 30_000));
			let password: string | undefined;
			if (probe.code !== 0) {
				const cached = cache.get(host);
				if (cached === undefined) {
					const given = await askPassword(ctx, host, params.command);
					if (given === null) return fail(host, "User declined the password prompt.");
					cache.set(host, given);
					password = given;
				} else {
					const ok = await ctx.ui.confirm(`sudo on ${host}`, params.command);
					if (!ok) return fail(host, "User declined the command.");
					password = cached;
				}
			}

			const r = await runSsh(host, sudoWrap(params.command, params.user), password, signal, timeoutMs);
			const text = scrub(r.output, password);
			const authFailure =
				password !== undefined && /incorrect password attempt|authentication failure/i.test(text);
			if (authFailure) cache.delete(host);
			const body =
				text.length > 20000 ? `${text.slice(0, 10000)}\n...truncated...\n${text.slice(-9000)}` : text;
			const summary = [
				`host: ${host}`,
				`exit: ${r.code}`,
				r.timedOut ? "timed out" : null,
				authFailure ? "wrong password; cache cleared" : null,
			]
				.filter(Boolean)
				.join(", ");
			return {
				content: [{ type: "text" as const, text: `${summary}\n${body}` }],
				details: { host, exitCode: r.code, authFailure } as SudoDetails,
				isError: r.code !== 0,
			};
		},
		renderCall(args, theme) {
			const head =
				theme.fg("toolTitle", theme.bold("sudo_ssh ")) + theme.fg("muted", `${args.host} `);
			return new Text(head + theme.fg("text", truncateToWidth(args.command ?? "", 140, "...")), 0, 0);
		},
		renderResult(result, _options, theme) {
			const d = result.details as SudoDetails | undefined;
			const state = result.isError ? theme.fg("error", "failed") : theme.fg("success", "ok");
			const note = d?.authFailure ? theme.fg("warning", " wrong password") : "";
			return new Text(`${state} ${theme.fg("dim", `exit ${d?.exitCode ?? "?"}`)}${note}`, 0, 0);
		},
	});

	pi.registerCommand("sudopw", {
		description: "Cache or clear a sudo password",
		handler: async (args, ctx) => {
			const arg = args.trim();
			if (arg === "forget") {
				cache.clear();
				ctx.ui.notify("Passwords cleared", "info");
				return;
			}
			if (!arg) {
				ctx.ui.notify("Usage: /sudopw <host> or forget", "info");
				return;
			}
			const given = await askPassword(ctx, arg, "cached for later sudo_ssh calls");
			if (given === null) {
				ctx.ui.notify("Cancelled", "warning");
				return;
			}
			cache.set(arg, given);
			ctx.ui.notify(`Password cached for ${arg}`, "info");
		},
	});

	pi.on("session_shutdown", () => {
		cache.clear();
	});
}
