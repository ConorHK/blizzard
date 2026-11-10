/** Writes one terminal label in call order, so a clear never lands before an older set. */
export function labeller(write: (value: string) => Promise<unknown>): (link: string | undefined) => Promise<void> {
	let last: Promise<unknown> = Promise.resolve();
	return (link) => {
		// The pane header opens the link, so anything but https is written as empty.
		const value = link?.startsWith("https://") ? link : "";
		last = last.then(() => write(value)).catch(() => undefined);
		return last.then(() => undefined);
	};
}
