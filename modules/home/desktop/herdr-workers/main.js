// Shows the focused tab's sub-agents in an equal grid right of its panes.
// Lives in a zero-size layout block and edits the layout with layout.set.

import { View, div } from "gpui-kit";
import { appHome, focused, layout, panes, props, readTextFile, run, settings, shared, terminals } from "herdr";

// Logical px the layout spends beside the grid: sidebar, padding and gap.
const CHROME = 268 + 16 + 8;
const MAIN_WEIGHT = 2;
const GRID_WEIGHT = 3;
// Narrowest worker column, about 45 characters of creeper.
const MIN_COLUMN = 360;
const GAP = 8;

function findNode(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const hit = findNode(child, id);
    if (hit) return hit;
  }
  return null;
}

function tabWorkers() {
  const tab = focused()?.tab;
  if (!tab) return [];
  const parents = new Set(panes().filter((p) => p.tab === tab && p.terminal).map((p) => p.terminal));
  return terminals()
    .filter((t) => t.state === "live" && parents.has(t.parent) && !t.labels?.["herdr.tab"])
    .sort((a, b) => (a.created_ms ?? 0) - (b.created_ms ?? 0))
    .map((t) => t.address);
}

function grid(workers, width) {
  const area = ((width - CHROME) * GRID_WEIGHT) / (MAIN_WEIGHT + GRID_WEIGHT);
  const most = Math.max(1, Math.floor(area / MIN_COLUMN));
  const rows = Math.ceil(workers.length / most);
  const cols = Math.ceil(workers.length / rows);
  const children = [];
  for (let r = 0; r < rows; r++) {
    children.push({
      id: `workers-row-${r}`,
      type: "row",
      gap: GAP,
      children: workers.slice(r * cols, (r + 1) * cols).map((address) => ({
        id: `worker-${address}`,
        type: "block",
        background: "background",
        border: { width: 1, color: "border" },
        content: { terminal: address },
      })),
    });
  }
  return { id: "workers", type: "column", size: { weight: GRID_WEIGHT }, gap: GAP, children };
}

export default class Workers extends View {
  init(_props, cx) {
    this.width = 1920;
    cx.spawn(async (cx) => {
      const text = await readTextFile(`${appHome()}/window.json`).catch(() => null);
      const bounds = text ? JSON.parse(text).bounds : null;
      if (bounds) this.width = bounds[2];
      cx.notify();
    });
  }

  sync() {
    if (shared("layout") !== props()?.layout) return;
    // The mod runtime has no structuredClone.
    const tree = JSON.parse(JSON.stringify(layout()));
    const body = findNode(tree, "work-body");
    const main = findNode(tree, "main");
    if (!body || !main) return;
    const before = JSON.stringify(body);
    body.children = body.children.filter((c) => c.id !== "workers");
    const workers = tabWorkers();
    if (workers.length) {
      main.size = { weight: MAIN_WEIGHT };
      const zoom = settings().zoom ?? 1;
      body.children.splice(body.children.indexOf(main) + 1, 0, grid(workers, this.width / zoom));
    } else {
      delete main.size;
    }
    if (JSON.stringify(body) !== before) run("layout.set", { layout: tree });
  }

  render() {
    this.sync();
    return div();
  }
}
