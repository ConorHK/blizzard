// Transcript card for advisor notes.
import { getMarkdownTheme, type Theme, type ThemeColor } from "@earendil-works/pi-coding-agent";
import { type Component, Markdown, truncateToWidth } from "@earendil-works/pi-tui";
import type { Severity } from "./guard.ts";

export interface NoteDetails {
	note: string;
	severity: Severity;
	advisor?: string;
}

const COLORS: Record<Severity, ThemeColor> = { nit: "accent", concern: "warning", blocker: "error" };
// An inverse space draws a solid bar.
const BAR = "\x1b[7m \x1b[27m";

export class NoteCard implements Component {
	private readonly body: Markdown;
	private readonly details: NoteDetails;
	private readonly theme: Theme;
	private readonly pad: number;
	private readonly expanded: boolean;

	constructor(details: NoteDetails, theme: Theme, pad: number, expanded: boolean) {
		this.details = details;
		this.theme = theme;
		this.pad = pad;
		this.expanded = expanded;
		this.body = new Markdown(details.note, 0, 0, getMarkdownTheme(), {
			color: text => theme.fg("customMessageText", text),
		});
	}

	render(width: number): string[] {
		const { theme, details } = this;
		const color = COLORS[details.severity] ?? COLORS.nit;
		const rail = `${" ".repeat(this.pad)}${theme.fg(color, BAR)} `;
		const inner = Math.max(10, width - this.pad - 2);
		let head = `${theme.fg(color, theme.bold("Advisor"))} ${theme.fg(color, details.severity)}`;
		if (this.expanded && details.advisor) head += ` ${theme.fg("dim", details.advisor)}`;
		const lines = [truncateToWidth(head, inner), ...this.body.render(inner)];
		return lines.map(line => rail + line);
	}

	invalidate(): void {
		this.body.invalidate();
	}
}
