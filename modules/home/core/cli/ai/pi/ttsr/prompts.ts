import { readFileSync } from "node:fs";

const cache = new Map<string, string>();

function load(name: string): string {
	let text = cache.get(name);
	if (text === undefined) {
		text = readFileSync(new URL(`./prompts/${name}.md`, import.meta.url), "utf8");
		cache.set(name, text);
	}
	return text;
}

/** Renders `{{var}}` and `{{#if var}}...{{/if}}`. */
export function render(name: string, vars: Record<string, string | undefined>): string {
	return load(name)
		.replace(/\{\{#if (\w+)\}\}([\s\S]*?)\{\{\/if\}\}/g, (_, key: string, body: string) => (vars[key] ? body : ""))
		.replace(/\{\{(\w+)\}\}/g, (_, key: string) => vars[key] ?? "")
		.trim();
}
