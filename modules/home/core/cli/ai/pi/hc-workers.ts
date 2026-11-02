// Starts pi workers as herdr-core terminals, so herdr-app shows them as sub-agents.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const Params = Type.Object({
	task: Type.String({ description: "the worker's first message: what to do and what to report" }),
	name: Type.Optional(
		Type.String({ description: "short unique name, 1-32 of a-z 0-9 - _ (e.g. fix-auth)" }),
	),
	cwd: Type.Optional(Type.String({ description: "working directory (default: this session's)" })),
	model: Type.Optional(Type.String({ description: "pi --model pattern (default: pi's default)" })),
});

const NAME = /^[a-z0-9_-]{1,32}$/;

function fail(text: string) {
	return { content: [{ type: "text" as const, text }], details: {}, isError: true };
}

export default function hcWorkers(pi: ExtensionAPI) {
	pi.registerTool({
		name: "hc_worker",
		label: "hc worker",
		description:
			"Start a pi worker in its own herdr-app pane. It runs as a herdr-core sub-agent of this session, gets the task as its first message, and reports back with hc send. Returns its address.",
		parameters: Params,
		promptSnippet: "Start pi workers that show in their own herdr-app panes.",
		promptGuidelines: [
			"Use hc_worker when the user asks for workers or subworkers they can watch in herdr.",
			"Give each worker a self-contained task and one short name.",
			"Wait with `hc wait <address>`; read results from the reports hc types into this session.",
		],
		async execute(_id, params, signal, _onUpdate, ctx) {
			const parent = process.env.HC_TERMINAL_ID;
			if (!parent) return fail("hc_worker needs a herdr-core terminal; HC_TERMINAL_ID is unset.");
			if (params.name !== undefined && !NAME.test(params.name)) {
				return fail(`Bad name "${params.name}": use 1-32 of a-z 0-9 - _.`);
			}
			const cwd = params.cwd ?? ctx.cwd;
			const task = `${params.task}\n\nWhen done or stuck, report to your parent with: hc send ${parent} "<result or blocker>"`;
			const piArgs = [...(params.model ? ["--model", params.model] : []), ...(params.name ? ["--name", params.name] : []), task];
			const args = ["run", "--bg", "--json", "--cwd", cwd, ...(params.name ? ["--name", params.name] : []), "--", "pi", ...piArgs];
			const r = await pi.exec("hc", args, { signal, cwd, timeout: 30_000 });
			if (r.code !== 0) return fail(`hc run failed (${r.code}): ${(r.stderr || r.stdout).trim()}`);
			const started = JSON.parse(r.stdout) as { address: string; name?: string | null };
			return {
				content: [{ type: "text" as const, text: `Started worker ${started.name ?? started.address} at ${started.address}.` }],
				details: started,
			};
		},
	});
}
