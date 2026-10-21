// Markdown notes as ordered "## " sections.

export interface Section {
	name: string;
	body: string;
}

export interface Note {
	head: string;
	sections: Section[];
}

export const TASK_ORDER = ["Goal", "Status", "Next", "Decisions", "Findings", "Links", "Log", "Workers"];

export function parseNote(text: string): Note {
	const parts = text.split(/^## (.+)\n/m);
	const sections: Section[] = [];
	for (let i = 1; i < parts.length; i += 2) {
		sections.push({ name: parts[i].trim(), body: parts[i + 1].trim() });
	}
	return { head: `${parts[0].trimEnd()}\n`, sections };
}

export function renderNote(note: Note): string {
	const body = note.sections.map((section) => `## ${section.name}\n\n${section.body ? `${section.body}\n\n` : ""}`);
	return `${note.head}\n${body.join("")}`.replace(/\n+$/, "\n");
}

export function getSection(note: Note, name: string): string {
	return note.sections.find((section) => section.name === name)?.body ?? "";
}

/** Inserts missing sections in TASK_ORDER. */
export function setSection(note: Note, name: string, body: string): Note {
	const sections = note.sections.map((section) => (section.name === name ? { name, body } : section));
	if (!note.sections.some((section) => section.name === name)) {
		const rank = TASK_ORDER.indexOf(name);
		const index = sections.findIndex((section) => {
			const other = TASK_ORDER.indexOf(section.name);
			return rank !== -1 && other > rank;
		});
		sections.splice(index === -1 ? sections.length : index, 0, { name, body });
	}
	return { ...note, sections };
}

export function appendLines(note: Note, name: string, lines: string[]): Note {
	if (lines.length === 0) return note;
	const body = getSection(note, name);
	return setSection(note, name, [body, ...lines].filter(Boolean).join("\n"));
}
