export interface TaskLabel {
	link?: string;
	title?: string;
}

const MAX_TITLE = 200;

/** The terminal labels for a task: its link (https only, since the pane header opens it) and title. */
export function labelValues(task: TaskLabel | undefined): string[] {
	const link = task?.link?.startsWith("https://") ? task.link : "";
	const title = link ? (task?.title ?? "").replace(/\s+/g, " ").trim().slice(0, MAX_TITLE) : "";
	return [`ogham.link=${link}`, `ogham.title=${title}`];
}

/** Writes the task labels in call order, so a clear never lands before an older set. */
export function labeller(write: (values: string[]) => Promise<unknown>): (task: TaskLabel | undefined) => Promise<void> {
	let last: Promise<unknown> = Promise.resolve();
	return (task) => {
		const values = labelValues(task);
		last = last.then(() => write(values)).catch(() => undefined);
		return last.then(() => undefined);
	};
}
