// Mirrors a picker as an @eko24ive/pi-ask form, so Ovis Chat can show and answer it.
import { randomUUID } from "node:crypto";
import type { EventBus } from "@earendil-works/pi-coding-agent";
import type { PickItem, Picked } from "./picker.ts";

const STARTED = "@eko24ive/pi-ask:started";
const COMPLETED = "@eko24ive/pi-ask:completed";
const SUBMIT = "@eko24ive/pi-ask:submit";
const RESULT = "@eko24ive/pi-ask:submit-result";
/** Ovis takes a form with no ask_user call only from this source. */
export const FORM_SOURCE = "ogham";
/** Ovis drops a question with more options than this. */
export const MAX_OPTIONS = 50;
const QUESTION = "task";

interface Submit {
	requestId?: unknown;
	flowId?: unknown;
	response?: { kind?: unknown; answers?: Record<string, { values?: unknown; customText?: unknown } | undefined> };
}

export interface RemoteForm {
	update(items: PickItem[]): void;
	close(): void;
}

/** A typed answer comes back as text, an empty one as a skip. */
export function remoteForm(events: EventBus, title: string, items: PickItem[], finish: (picked: Picked | undefined) => void): RemoteForm {
	const flowId = `ogham-${randomUUID()}`;
	let shown = items.slice(0, MAX_OPTIONS);
	let open = true;

	function announce() {
		const options = shown.map(({ value, label, hint }) => ({ value, label, ...(hint ? { description: hint } : {}) }));
		const questions = [{ id: QUESTION, prompt: title, type: "single", options }];
		events.emit(STARTED, { version: 1, flowId, source: FORM_SOURCE, title, questions, createdAt: Date.now() });
	}

	function close() {
		if (!open) return;
		open = false;
		stop();
		events.emit(COMPLETED, { version: 1, flowId });
	}

	const stop = events.on(SUBMIT, (data) => {
		const { requestId, flowId: id, response } = (data ?? {}) as Submit;
		if (id !== flowId) return;
		const reply = (result: object) => events.emit(RESULT, { version: 1, requestId, flowId, ...result });
		const answer = response?.kind === "answer" ? response.answers?.[QUESTION] : undefined;
		const text = typeof answer?.customText === "string" ? answer.customText.trim() : "";
		const value = Array.isArray(answer?.values) ? answer.values[0] : undefined;
		let picked: Picked | undefined;
		if (text) picked = { text };
		else if (value !== undefined) {
			if (!shown.some((item) => item.value === value)) {
				reply({ ok: false, error: "invalid_answer", message: "That task is no longer offered." });
				return;
			}
			picked = { value: value as string };
		}
		reply({ ok: true });
		close();
		finish(picked);
	});

	announce();
	return {
		update(next) {
			shown = next.slice(0, MAX_OPTIONS);
			if (open) announce();
		},
		close,
	};
}
