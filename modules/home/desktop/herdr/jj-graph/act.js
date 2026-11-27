import { exec, notify, setShared, openOverlay, spaces, panes, run } from "herdr";
import { commandsFor, dialogFor, dialogHeight, doneText, jjError } from "./jj.js";

// Runs an action's jj commands in order, stopping at the first failure. Every
// graph copy refreshes after, whether or not its watch saw the change.
export async function perform(action, values, ctx, { toast = true } = {}) {
  try {
    if (action.type === "removeWorkspace") closeSpace(action, ctx.on);
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

const inside = (p, dir) => p === dir || p.startsWith(`${dir}/`);

// The space whose first terminal sits in a workspace.
function spaceIn(w, on) {
  return spaces().find((s) => {
    if ((s.machine ?? null) !== (on ?? null)) return false;
    const tabs = new Set((s.tabs ?? []).map((c) => c.id));
    const at = panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
    return Boolean(at) && Boolean(w.path) && inside(at, w.path);
  });
}

function closeSpace(w, on) {
  const space = spaceIn(w, on);
  if (space) run("space.close", { id: space.id, confirmed: true });
}

// The terminal pane in a workspace, agents first, then the focused one.
function paneIn(w, on) {
  if (!w.path) return null;
  const spaceOf = new Map(spaces().filter((s) => (s.machine ?? null) === (on ?? null))
    .flatMap((s) => (s.tabs ?? []).map((t) => [t.id, s])));
  const rank = (p) => (p.program?.agent ? 2 : 0) + (p.focused ? 1 : 0);
  const pane = panes().filter((p) => p.terminal && p.cwd && spaceOf.has(p.tab) && inside(p.cwd, w.path))
    .sort((a, b) => rank(b) - rank(a))[0];
  return pane ? { pane, space: spaceOf.get(pane.tab) } : null;
}

// Shows the tab with a workspace's agent or terminal, else its space, else opens one there.
export function showSpace(w, on) {
  const hit = paneIn(w, on);
  if (hit) {
    run("space.select", { id: hit.space.id });
    run("tab.select", { id: hit.pane.tab });
    run("pane.focus", { pane: hit.pane.pane });
    return;
  }
  const space = spaceIn(w, on);
  if (space) run("space.select", { id: space.id });
  else run("space.new", { name: w.name, folder: w.path, machine: on ?? "" });
}

// Opens the action's dialog; false when it has none and should run at once.
export function openDialog(action, ctx) {
  const spec = dialogFor(action, ctx);
  if (!spec) return false;
  openOverlay({ mod: "jj-graph", kind: "dialog", width: 460, height: dialogHeight(spec), props: { role: "dialog", action, ctx } });
  return true;
}
