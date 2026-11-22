import { exec, notify, setShared, openOverlay } from "herdr";
import { commandsFor, dialogFor, dialogHeight, doneText, jjError } from "./jj.js";

// Runs an action's jj commands in order, stopping at the first failure. Every
// graph copy refreshes after, whether or not its watch saw the change.
export async function perform(action, values, ctx, { toast = true } = {}) {
  try {
    for (const args of commandsFor(action, values, ctx)) {
      const result = await exec("jj", args, { cwd: ctx.root, on: ctx.on });
      if (result.code !== 0) {
        const message = jjError(result);
        if (toast) notify({ title: "jj refused", body: message, level: "error" });
        return { ok: false, message };
      }
    }
    notify({ title: doneText(action, values), level: "success", timeout: 3000 });
    return { ok: true };
  } catch (e) {
    const message = String(e?.message ?? e);
    if (toast) notify({ title: "jj didn't run", body: message, level: "error" });
    return { ok: false, message };
  } finally {
    setShared("jj-graph.changed", Date.now());
  }
}

// Opens the action's dialog; false when it has none and should run at once.
export function openDialog(action, ctx) {
  const spec = dialogFor(action, ctx);
  if (!spec) return false;
  openOverlay({ mod: "jj-graph", kind: "dialog", width: 460, height: dialogHeight(spec), props: { role: "dialog", action, ctx } });
  return true;
}
