// Reports herdr:blocked waits, such as ask_user, as OSC 7501 blocked status.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { formatProgramStatus, type ProgramStatus } from "@earendil-works/pi-tui";

interface BlockedEvent {
	active: boolean;
	label?: string;
}

// Pi reports only after the terminal answers its query, so mirror that by env.
function canReport(): boolean {
	const forced = process.env.PI_PROGRAM_STATUS;
	if (forced === "0") return false;
	return process.stdout.isTTY && (forced === "1" || process.env.HC_TERMINAL_ID !== undefined);
}

export default function blockedStatus(pi: ExtensionAPI) {
	if (!canReport()) return;
	let open = 0;
	let idle = () => false;
	pi.on("session_start", (_event, ctx) => {
		idle = () => ctx.isIdle();
	});

	pi.events.on("herdr:blocked", (data) => {
		const event = data as BlockedEvent;
		open = Math.max(0, open + (event.active ? 1 : -1));
		// Pi's own reporter only speaks on run events, so restore its state ourselves.
		const status: ProgramStatus =
			open > 0
				? { state: "blocked", kind: "question", message: event.label ?? "Waiting for you", app: "pi" }
				: idle()
					? { state: "idle", app: "pi" }
					: { state: "working", message: pi.getSessionName(), app: "pi" };
		process.stdout.write(formatProgramStatus(status));
	});
}
