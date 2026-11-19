// Splits the focused pane dwindle style: right at even depth, down at odd.
// Opened by mod.open:bsp as an invisible popup that closes itself.

import { View, div } from "gpui-kit";
import { closeOverlay, focused, panes, props, run, setShared, shared } from "herdr";

const KEY = "bsp.depth";

const tabPanes = (tab) =>
  panes()
    .filter((p) => p.tab === tab)
    .map((p) => p.pane);

export default class Bsp extends View {
  init(_props, cx) {
    const f = focused();
    if (!f?.pane) return this.done();
    const depths = shared(KEY) ?? {};
    const depth = depths[f.pane] ?? 0;
    this.split = { pane: f.pane, tab: f.tab, depth: depth + 1, before: new Set(tabPanes(f.tab)) };
    run("pane.split", { pane: f.pane, direction: depth % 2 ? "down" : "right" });
    this.record();
    // The new pane can show up a frame later, so retry before giving up.
    this.retry = cx.timer.every(50, () => this.record());
    cx.timer.after(1000, () => this.done());
  }

  record() {
    const s = this.split;
    if (!s) return;
    const now = tabPanes(s.tab);
    const added = now.find((p) => !s.before.has(p));
    if (!added) return;
    const live = new Set(panes().map((p) => p.pane));
    const depths = Object.fromEntries(Object.entries(shared(KEY) ?? {}).filter(([p]) => live.has(p)));
    depths[s.pane] = s.depth;
    depths[added] = s.depth;
    setShared(KEY, depths);
    this.done();
  }

  done() {
    this.split = null;
    this.retry?.cancel();
    const overlay = props()?.overlay;
    if (overlay && !this.closed) {
      this.closed = true;
      closeOverlay(overlay);
    }
  }

  render() {
    return div();
  }
}
