// Copies code from the last reply, unwrapped.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { copyToClipboard } from "@earendil-works/pi-coding-agent";
import { extractSnippets, snippetLabel, snippetPreview } from "./snippets.ts";

function latestSnippets(ctx: ExtensionContext): string[] {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i];
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const text = entry.message.content
			.flatMap((part) => (part.type === "text" ? [part.text] : []))
			.join("\n");
		const snippets = extractSnippets(text);
		if (snippets.length > 0) return snippets;
	}
	return [];
}

async function pickSnippet(ctx: ExtensionContext, snippets: string[], arg: string) {
	const wanted = Number.parseInt(arg, 10);
	if (Number.isInteger(wanted)) {
		if (wanted >= 1 && wanted <= snippets.length) return snippets[wanted - 1];
		ctx.ui.notify(`No snippet ${wanted}; ${snippets.length} found.`, "warning");
		return undefined;
	}
	if (snippets.length === 1) return snippets[0];
	const labels = snippets.map(snippetLabel);
	const choice = await ctx.ui.select("Copy which snippet?", labels);
	return choice === undefined ? undefined : snippets[labels.indexOf(choice)];
}

async function copySnippet(ctx: ExtensionContext, arg = "") {
	const snippets = latestSnippets(ctx);
	if (snippets.length === 0) {
		ctx.ui.notify("No code in recent replies.", "warning");
		return;
	}
	const snippet = await pickSnippet(ctx, snippets, arg.trim());
	if (snippet === undefined) return;
	try {
		await copyToClipboard(snippet);
		ctx.ui.notify(`Copied: ${snippetPreview(snippet)}`, "info");
	} catch (error) {
		ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
	}
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("copy-code", {
		description: "Copy a code snippet from the last reply",
		handler: (arg, ctx) => copySnippet(ctx, arg),
	});
	pi.registerShortcut("ctrl+alt+c", {
		description: "Copy a code snippet from the last reply",
		handler: (ctx) => copySnippet(ctx),
	});
}
