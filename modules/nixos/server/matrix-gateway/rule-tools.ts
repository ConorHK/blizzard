import { request } from "node:http";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

interface Rule {
	id: string;
	name: string;
	chat?: string;
	sender?: string;
	match?: string;
	about?: string;
	instruction: string;
	enabled: boolean;
	revision: number;
	feedback?: { time: string; text: string }[];
}

const socketPath = process.env.MATRIX_RULES_SOCKET ?? "";

function call<T>(method: string, path: string, body?: unknown): Promise<T> {
	return new Promise((resolve, reject) => {
		const payload = body === undefined ? undefined : JSON.stringify(body);
		const req = request(
			{ socketPath, path, method, headers: payload ? { "Content-Type": "application/json" } : {} },
			(res) => {
				const chunks: Buffer[] = [];
				res.on("data", (chunk: Buffer) => chunks.push(chunk));
				res.on("end", () => {
					try {
						const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
						if (res.statusCode !== 200) reject(new Error(parsed.error ?? `status ${res.statusCode}`));
						else resolve(parsed as T);
					} catch (err) {
						reject(err);
					}
				});
				res.on("error", reject);
			},
		);
		req.on("error", reject);
		if (payload) req.write(payload);
		req.end();
	});
}

function text(value: string) {
	return { content: [{ type: "text" as const, text: value }], details: undefined };
}

function describe(r: Rule): string {
	const filters = [
		r.chat && `chat contains "${r.chat}"`,
		r.sender && `sender contains "${r.sender}"`,
		r.match && `regex /${r.match}/`,
		r.about && `about "${r.about}"`,
	].filter(Boolean);
	const lines = [
		`${r.id} "${r.name}" rev ${r.revision}${r.enabled ? "" : " (disabled)"}`,
		`  when: ${filters.join(" and ")}`,
		`  do: ${r.instruction}`,
	];
	for (const f of (r.feedback ?? []).slice(-3)) lines.push(`  feedback: ${f.text}`);
	return lines.join("\n");
}

const filterFields = {
	chat: Type.Optional(Type.String({ description: "Part of the chat name, case-insensitive." })),
	sender: Type.Optional(Type.String({ description: "Part of the sender's name, case-insensitive." })),
	match: Type.Optional(Type.String({ description: "RE2 regex the message text must match, e.g. (?i)rent|deposit." })),
	about: Type.Optional(
		Type.String({ description: "Plain-language description the message must fit, checked by a model. Use for fuzzy topics." }),
	),
};

const listRules = defineTool({
	name: "list_rules",
	label: "List rules",
	description: "List the user's message rules with their filters, instructions and recent feedback.",
	parameters: Type.Object({}),
	async execute() {
		const rules = await call<Rule[]>("GET", "/rules");
		return text(rules.length === 0 ? "No rules yet." : rules.map(describe).join("\n\n"));
	},
});

const addRule = defineTool({
	name: "add_rule",
	label: "Add rule",
	description:
		"Create a rule that runs an instruction when a new message matches every filter given. Set at least one filter.",
	parameters: Type.Object({
		name: Type.String({ description: "Short name." }),
		instruction: Type.String({ description: "What to do with a matching message, e.g. summarise it in one line." }),
		...filterFields,
	}),
	async execute(_id, params) {
		return text(`Created:\n${describe(await call<Rule>("POST", "/rules", params))}`);
	},
});

const updateRule = defineTool({
	name: "update_rule",
	label: "Update rule",
	description:
		"Change a rule. Omitted fields stay the same; an empty string clears a filter. Always give a note saying why.",
	parameters: Type.Object({
		id: Type.String({ description: "Rule id from list_rules." }),
		note: Type.String({ description: "Why the rule changed, usually the user's feedback." }),
		name: Type.Optional(Type.String()),
		instruction: Type.Optional(Type.String()),
		enabled: Type.Optional(Type.Boolean()),
		...filterFields,
	}),
	async execute(_id, params) {
		const { id, ...patch } = params;
		return text(`Updated:\n${describe(await call<Rule>("PATCH", `/rules/${encodeURIComponent(id)}`, patch))}`);
	},
});

const deleteRule = defineTool({
	name: "delete_rule",
	label: "Delete rule",
	description: "Delete a rule. Only call this after the user confirms.",
	parameters: Type.Object({ id: Type.String({ description: "Rule id from list_rules." }) }),
	async execute(_id, params) {
		await call("DELETE", `/rules/${encodeURIComponent(params.id)}`);
		return text(`Deleted ${params.id}.`);
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(listRules);
	pi.registerTool(addRule);
	pi.registerTool(updateRule);
	pi.registerTool(deleteRule);
}
