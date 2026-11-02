// Type-to-filter picker on a pi custom component.
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { fuzzyFilter, Input, truncateToWidth } from "@earendil-works/pi-tui";

export interface PickItem {
	value: string;
	label: string;
	hint?: string;
}

export type Picked = { value: string } | { text: string };

export interface PickerOptions {
	/** Offers the typed text as a new entry. */
	newLabel?: (text: string) => string;
	/** Hands back a setter for live item updates. */
	onOpen?: (setItems: (items: PickItem[]) => void) => void;
	maxVisible?: number;
}

const NEW = "\u0000new";

const haystack = (item: PickItem) => `${item.label} ${item.hint ?? ""}`;

/** The new row leads unless some item holds every typed word. */
export function filterItems(items: PickItem[], query: string, newLabel?: (text: string) => string): PickItem[] {
	const matched = fuzzyFilter(items, query, haystack);
	const text = query.trim();
	if (!text || !newLabel) return matched;
	const created = { value: NEW, label: newLabel(text) };
	const words = text.toLowerCase().split(/[\s/]+/).filter(Boolean);
	const close = matched.some((item) => words.every((word) => haystack(item).toLowerCase().includes(word)));
	return close ? [...matched, created] : [created, ...matched];
}

export function pick(ctx: ExtensionContext, title: string, initial: PickItem[], options: PickerOptions = {}): Promise<Picked | undefined> {
	return ctx.ui.custom<Picked | undefined>((tui, theme, keybindings, done) => {
		const max = options.maxVisible ?? 12;
		const input = new Input({ prompt: "Search: ", placeholder: "type to filter" });
		input.focused = true;
		let items = initial;
		let shown = filterItems(items, "", options.newLabel);
		let selected = 0;
		const refilter = () => {
			shown = filterItems(items, input.getValue(), options.newLabel);
			selected = Math.min(selected, Math.max(0, shown.length - 1));
		};
		options.onOpen?.((next) => {
			items = next;
			refilter();
			tui.requestRender();
		});
		const move = (by: number) => {
			selected = Math.max(0, Math.min(shown.length - 1, selected + by));
		};
		return {
			render(width: number) {
				const lines = [truncateToWidth(theme.fg("accent", theme.bold(title)), width), ...input.render(width)];
				const start = Math.max(0, Math.min(selected - Math.floor(max / 2), shown.length - max));
				for (const [offset, item] of shown.slice(start, start + max).entries()) {
					const active = start + offset === selected;
					const label = `${active ? "> " : "  "}${item.label}`;
					const hint = item.hint ? theme.fg("dim", `  ${item.hint}`) : "";
					lines.push(truncateToWidth(`${active ? theme.fg("accent", label) : label}${hint}`, width));
				}
				if (!shown.length) lines.push(theme.fg("warning", "  No matches"));
				if (shown.length > max) lines.push(theme.fg("dim", `  ${selected + 1} of ${shown.length}`));
				const tab = options.newLabel ? ", tab for new" : "";
				lines.push(truncateToWidth(theme.fg("dim", `type to filter, up/down to move${tab}, enter to pick, esc to skip`), width));
				return lines;
			},
			invalidate() {
				input.invalidate();
			},
			handleInput(data: string) {
				if (keybindings.matches(data, "tui.select.confirm")) {
					const item = shown[selected];
					if (item) done(item.value === NEW ? { text: input.getValue().trim() } : { value: item.value });
					return;
				}
				if (keybindings.matches(data, "tui.select.cancel")) {
					done(undefined);
					return;
				}
				if (keybindings.matches(data, "tui.input.tab")) {
					const index = shown.findIndex((item) => item.value === NEW);
					if (index !== -1) selected = index;
					tui.requestRender();
					return;
				}
				if (keybindings.matches(data, "tui.select.up")) move(-1);
				else if (keybindings.matches(data, "tui.select.down")) move(1);
				else if (keybindings.matches(data, "tui.select.pageUp")) move(-max);
				else if (keybindings.matches(data, "tui.select.pageDown")) move(max);
				else {
					input.handleInput(data);
					refilter();
					selected = 0;
				}
				tui.requestRender();
			},
		};
	});
}
