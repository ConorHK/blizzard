// Ported from oh-my-pi (MIT): advisor/emission-guard.ts.
// Models ignore prose budgets; enforce them here.

export type Severity = "nit" | "concern" | "blocker";
export type SuppressionReason = "empty" | "noise" | "duplicate" | "rate-limit";

export interface Admission {
	accepted: boolean;
	reason?: SuppressionReason;
	displacedKey?: string;
}

export const SEVERITY_RANK: Record<Severity, number> = { nit: 1, concern: 2, blocker: 3 };

export function normalizeNote(note: string): string {
	return note
		.toLowerCase()
		.normalize("NFKC")
		.replace(/[^\p{L}\p{N}]+/gu, " ")
		.trim();
}

const NOISE = new Set([
	"stop",
	"stop here",
	"stop now",
	"halt",
	"abort",
	"done",
	"task done",
	"task complete",
	"complete",
	"finished",
	"ok",
	"okay",
	"ok done",
	"no issue",
	"no issues",
	"no issue continue",
	"no concerns",
	"no concern",
	"nothing to add",
	"nothing to flag",
	"nothing to report",
	"no notes",
	"no further input",
	"no further input needed",
	"no further input required",
	"no further watcher input",
	"no further watcher input needed",
	"no further advice",
	"no further advice needed",
	"lgtm",
	"looks good",
	"all good",
	"agent is on track",
	"agent on track",
	"on track",
	"continue",
	"carry on",
]);

const HISTORY_CAPACITY = 4096;
export const MAX_BUDGET = 32;
export const DEFAULT_BUDGET = 4;

export class EmissionGuard {
	#seen = new Map<string, number>();
	#seenOrder: string[] = [];
	#slots: { key: string; rank: number; pending: boolean }[] = [];
	readonly #budget: number;

	constructor(budget = DEFAULT_BUDGET) {
		this.#budget = Number.isFinite(budget) ? Math.min(MAX_BUDGET, Math.max(1, Math.trunc(budget))) : DEFAULT_BUDGET;
	}

	reset(): void {
		this.#seen.clear();
		this.#seenOrder.length = 0;
		this.#slots = [];
	}

	beginUpdate(): void {
		this.#slots = [];
	}

	markRouted(note: string): void {
		const slot = this.#slots.find(s => s.key === normalizeNote(note));
		if (slot) slot.pending = false;
	}

	#record(key: string, rank: number): void {
		const isNew = !this.#seen.has(key);
		this.#seen.set(key, rank);
		if (!isNew) return;
		this.#seenOrder.push(key);
		if (this.#seenOrder.length > HISTORY_CAPACITY) {
			const stale = this.#seenOrder.shift();
			if (stale !== undefined) this.#seen.delete(stale);
		}
	}

	/** Noise, then rank-aware dedupe, then budget. */
	admit(note: string, opts: { rank: number; pending: boolean }): Admission {
		const key = normalizeNote(note);
		if (!key) return { accepted: false, reason: "empty" };
		if (NOISE.has(key)) return { accepted: false, reason: "noise" };
		const { rank } = opts;
		if (rank <= (this.#seen.get(key) ?? 0)) return { accepted: false, reason: "duplicate" };
		let displacedKey: string | undefined;
		const ownSlot = this.#slots.find(s => s.key === key);
		if (rank >= SEVERITY_RANK.blocker) {
			if (ownSlot?.pending) this.#slots.splice(this.#slots.indexOf(ownSlot), 1);
		} else if (ownSlot) {
			ownSlot.rank = rank;
		} else if (this.#slots.length < this.#budget) {
			this.#slots.push({ key, rank, pending: opts.pending });
		} else {
			let minIndex = -1;
			for (let i = 0; i < this.#slots.length; i++) {
				const slot = this.#slots[i];
				if (!slot.pending) continue;
				if (minIndex === -1 || slot.rank < this.#slots[minIndex].rank) minIndex = i;
			}
			if (minIndex === -1 || rank <= this.#slots[minIndex].rank) return { accepted: false, reason: "rate-limit" };
			displacedKey = this.#slots[minIndex].key;
			this.#slots[minIndex] = { key, rank, pending: opts.pending };
		}
		this.#record(key, rank);
		return { accepted: true, displacedKey };
	}
}

export type DeliveryChannel = "steer" | "aside" | "preserve";

/** Ported from resolveAdvisorDeliveryChannel. */
export function deliveryChannel(opts: {
	severity: Severity;
	autoResumeSuppressed: boolean;
	streaming: boolean;
	terminalAnswer: boolean;
	immune: boolean;
}): DeliveryChannel {
	if (opts.terminalAnswer && opts.severity !== "blocker" && !opts.streaming) return "preserve";
	if (opts.severity === "nit") return "aside";
	if (opts.autoResumeSuppressed && !opts.streaming) return "preserve";
	if (opts.immune && opts.severity !== "blocker") return "aside";
	return "steer";
}
