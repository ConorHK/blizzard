// The sidebar as a tree: each space a folder, its tabs folders in it, and in each tab its live
// agents and their sub-agents with their status. A folded folder shows its most urgent status.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, terminals, spaces, panes, machines, focused, run, theme, shared, setShared, setAgentOrder, openOverlay, props, window, layout } from "herdr";
import { followSpace } from "./space-layout.js";

const ICONS = "mods/workspace-chrome";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, as in the shipped mods.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", { id: "sidebar", px: narrow() ? (shared("sidebar.width") ?? 268) : window()?.platform === "macos" ? 76 : 44 });
}

// Space colors as the spaces mod stores them, since the picker reads them too.
const PALETTE = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };

const RANK = { blocked: 4, done: 3, working: 2, idle: 1 };
const urgent = (list) => list.reduce((m, s) => ((RANK[s] ?? 0) > (RANK[m] ?? 0) ? s : m), null);

// A sub-agent reports to its parent, so its done reads as idle and its error as blocked.
const kidStatus = (k, listed) => {
  const s = listed.get(k.address) ?? k.status;
  return s === "error" ? "blocked" : s === "done" ? "idle" : s;
};

// Drops a leading glyph, and a one-letter mark before " - " as pi titles have.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").replace(/^\S\s+-\s+/u, "").trim();

function lead(tab, ps) {
  const mine = ps.filter((p) => p.tab === tab.id && p.terminal);
  return mine.find((p) => p.program?.agent) ?? mine.find((p) => p.focused) ?? mine[0];
}

// A title says more than the program's name or a folder path does.
function telling(live, program) {
  return Boolean(live) && live !== program?.name && live.toLowerCase() !== program?.key && !/^[~/]|^[A-Za-z]:\\/.test(live) && !live.includes("@");
}

function tabName(tab, l) {
  const live = clean(l?.title);
  return (tab.name === l?.program?.name || !tab.named) && telling(live, l?.program) ? live : tab.name;
}

// The program, then its title when that says more than the tab's name does.
function agentLabel(a, tab) {
  const live = clean(a.title);
  const detail = telling(live, a.program) && live !== tab ? live : null;
  return { name: a.program?.name || a.app || a.address, detail };
}

function duration(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

function icon(p, size, color) {
  if (!p?.icon) return div().w(size).flex_none();
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

// A layout may fix every text size, for a bitmap font with one size.
let fixed = null;
const ts = (n) => fixed ?? n;

export default class Tree extends View {
  init(_props, cx) {
    this.folded = new Set(JSON.parse(localStorage.getItem("folded") ?? "[]"));
    // Each agent's last state and when it changed, kept across restarts.
    this.changed = JSON.parse(localStorage.getItem("changed") ?? "{}");
    this.listed = new Map();
    cx.timer.every(30000, (cx) => cx.notify());
  }

  fold(id, cx) {
    if (!this.folded.delete(id)) this.folded.add(id);
    const known = new Set([...spaces().flatMap((s) => [s.id, ...s.tabs.map((t) => t.id)]), ...terminals().map((t) => t.address)]);
    localStorage.setItem("folded", JSON.stringify([...this.folded].filter((f) => known.has(f))));
    cx.notify();
  }

  // Done and idle count as one: looking at a finished agent is not the agent doing anything.
  track(list, now) {
    let dirty = false;
    for (const a of list) {
      const s = a.status === "done" ? "idle" : a.status;
      if (this.changed[a.address]?.s === s) continue;
      this.changed[a.address] = { s, at: now };
      dirty = true;
    }
    if (!dirty) return;
    const listed = new Set(list.map((a) => a.address));
    for (const [k, c] of Object.entries(this.changed)) if (!listed.has(k) && now - c.at > 30 * 86400000) delete this.changed[k];
    localStorage.setItem("changed", JSON.stringify(this.changed));
  }

  // Gives each new space the least used color, but not while a machine's spaces are still loading.
  paint(sp) {
    if (machines().some((m) => m.layout === "loading")) return;
    const old = shared("space.colors") ?? {};
    const ids = new Set(sp.map((s) => s.id));
    const kept = Object.fromEntries(Object.entries(old).filter(([id]) => ids.has(id)));
    let changed = Object.keys(kept).length !== Object.keys(old).length;
    for (const s of sp) {
      if (kept[s.id] || s.name === "~") continue;
      const uses = (c) => Object.values(kept).filter((v) => v === c).length;
      kept[s.id] = PALETTE.reduce((best, c) => (uses(c) < uses(best) ? c : best));
      changed = true;
    }
    if (changed) setShared("space.colors", kept);
  }

  menu(spec) {
    openOverlay({ mod: props()?.menu ?? "menu", kind: "popup", width: 200, height: 260, props: spec });
  }

  // Live sub-agents of `addr`, depth first.
  tree(all, addr, depth = 0) {
    return all
      .filter((k) => k.parent === addr && k.state === "live")
      .flatMap((k) => [{ k, depth }, ...this.tree(all, k.address, depth + 1)]);
  }

  status(t, status, compact = false) {
    if (status === "working") return svg(`${ICONS}/spinner.svg`).size(12).mx(1).flex_none().text_color(t.working).spin(900);
    if (status === "blocked" && compact) return div().size(14).flex_none().rounded(4).bg(t.blocked + "26").text_size(ts(10.5)).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!");
    if (status === "blocked") return div().flex_none().px(6).h(18).rounded(5).bg(t.blocked + "26").text_size(ts(10.5)).font_semibold().text_color(t.blocked).flex().items_center().child("Needs you");
    if (status === "idle") return div().size(7).mx(3).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim);
    return div().size(7).mx(3).flex_none().rounded(4).bg(status === "done" ? t.done : t.dim + "00");
  }

  chevron(id, open, t) {
    return div().id(`fold-${id}`).w(14).h(18).flex_none().flex().items_center().justify_center().rounded(4).text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        this.fold(id, cx);
      })
      .child(svg(`${ICONS}/chevron-${open ? "down" : "right"}.svg`).size(11));
  }

  row(id, level, t) {
    return h_flex().id(id).h(26).flex_none().pl(4 + level * 14).pr(6).gap(6).items_center().rounded(6).cursor_pointer()
      .hover((s) => s.bg(t.hover));
  }

  // A drag starts on a top-level agent's row; it moves once the pointer travels a few pixels.
  grab(el, a) {
    return el
      .when(Boolean(this.drag?.moved) && this.drag.a.address === a.address, (el) => el.opacity(0.5))
      .on_mouse_down("left", (e) => {
        this.drag = { a, x: e.position.x, y: e.position.y, moved: false };
      });
  }

  // Agents move within their machine, and never to where they already are.
  fits(a, s, tab) {
    const sp = spaces();
    const from = sp.find((x) => x.id === a.space);
    if ((from?.machine ?? null) !== (s.machine ?? null)) return false;
    if (tab) return tab.id !== a.tab;
    return !(s.id === a.space && from?.tabs.find((x) => x.id === a.tab)?.panes === 1);
  }

  // Dropping on a tab splits the agent in beside its panes; on a space, it gets a tab there.
  drop(el, s, tab, t) {
    const key = tab ? `tb:${tab.id}` : `sp:${s.id}`;
    return el
      .when(this.over === key, (el) => el.border(1).border_color(t.accent))
      .on_mouse_move((e, cx) => {
        const d = this.drag;
        if (!d) return;
        if (!d.moved) {
          if (Math.hypot(e.position.x - d.x, e.position.y - d.y) < 4) return;
          d.moved = true;
          cx.notify();
        }
        const over = this.fits(d.a, s, tab) ? key : null;
        if (this.over === over) return;
        this.over = over;
        cx.notify();
      })
      .on_mouse_up("left", (_e, cx) => {
        if (this.drag?.moved && this.over === key) this.move(this.drag.a, s, tab, cx);
      });
  }

  move(a, s, tab, cx) {
    const from = spaces().flatMap((x) => x.tabs).find((x) => x.id === a.tab);
    // A tab that held only this agent moves whole, so its name goes with it.
    const name = from?.named && from.panes === 1 ? from.name : "";
    // Focus comes back afterwards, unless the moved agent had it.
    const back = focused()?.pane;
    run("terminal.park", { terminal: a.address });
    cx.spawn(async (cx) => {
      // Park finishes in the background, and keep needs the old pane gone.
      if (!(await this.until(cx, () => !panes().some((p) => p.terminal === a.address)))) return;
      try {
        if (tab) {
          const into = panes().find((p) => p.tab === tab.id && p.terminal) ?? panes().find((p) => p.tab === tab.id);
          if (into) run("pane.focus", { pane: into.pane });
          run("terminal.keep", { terminal: a.address, place: into ? "right" : "tab" });
        } else {
          run("space.select", { id: s.id });
          run("terminal.keep", { terminal: a.address, place: "tab" });
        }
      } catch {
        // The check below gives it a tab of its own.
      }
      let pane = await this.until(cx, () => panes().find((p) => p.terminal === a.address));
      // A parked agent has no pane, so a failed keep must not strand it.
      if (!pane) {
        run("terminal.keep", { terminal: a.address, place: "tab" });
        pane = await this.until(cx, () => panes().find((p) => p.terminal === a.address));
      }
      if (pane && !tab) run("tab.rename", { id: pane.tab, name });
      if (back && back !== a.pane && panes().some((p) => p.pane === back)) run("pane.focus", { pane: back });
      cx.notify();
    });
  }

  letGo(cx) {
    if (!this.drag) return;
    this.drag = null;
    this.over = null;
    cx.notify();
  }

  // Polls live data until `test` returns something, for at most two seconds.
  async until(cx, test) {
    for (let i = 0; i < 40; i++) {
      const found = test();
      if (found) return found;
      await cx.sleep(50);
    }
    return null;
  }

  spaceRow(s, t) {
    const open = !this.folded.has(s.id);
    const color = (shared("space.colors") ?? {})[s.id] ?? "ansi6";
    const fill = color.startsWith("#") ? color : (MARK[color] ?? t[color]);
    return this.drop(this.row(`sp-${s.id}`, 0, t), s, null, t)
      .on_click(() => run("space.select", { id: s.id }))
      .on_mouse_down("right", () => this.menu({ tab: "space", target: { id: s.id } }))
      .child(this.chevron(s.id, open, t))
      .child(svg(`${ICONS}/folder.svg`).size(14).flex_none().text_color(fill))
      .child(div().flex_1().min_w(0).truncate().font_semibold().text_color(s.active ? t.foreground : t.muted).child(s.name))
      .when(!open && Boolean(s.status) && s.status !== "idle", (el) => el.child(this.status(t, s.status, true)))
      .child(div().id(`tab-new-${s.id}`).size(20).flex_none().flex().items_center().justify_center().rounded(5).text_color(t.dim)
        .hover((st) => st.bg(t.hover).text_color(t.foreground))
        .tooltip("New tab here")
        .on_click((_e, cx) => {
          cx.stop_propagation();
          // The new-tab menu opens its tabs in the shown space, so show this one first.
          run("space.select", { id: s.id });
          cx.spawn(async (cx) => {
            await this.until(cx, () => spaces().find((x) => x.active)?.id === s.id);
            openOverlay({ mod: props()?.newMenu ?? "new-menu", kind: "popup", width: 250, height: 512 });
          });
        })
        .child(svg(`${ICONS}/plus.svg`).size(12)));
  }

  tabRow(s, tab, label, hasAgents, t) {
    const open = !this.folded.has(tab.id);
    const shown = s.active && tab.active;
    return this.drop(this.row(`tb-${tab.id}`, 1, t), s, tab, t)
      .when(shown, (el) => el.bg(t.selected))
      .on_click(() => {
        run("space.select", { id: s.id });
        run("tab.select", { id: tab.id });
      })
      .on_mouse_down("right", () => this.menu({ tab: "tab", target: { id: tab.id, space: s.id } }))
      .child(hasAgents ? this.chevron(tab.id, open, t) : div().w(14).flex_none())
      .child(svg(`${ICONS}/folder.svg`).size(13).flex_none().text_color(shown ? t.accent : t.dim))
      .child(div().flex_1().min_w(0).truncate().text_color(shown ? t.foreground : t.muted).child(label))
      .when(!open && Boolean(tab.status) && tab.status !== "idle", (el) => el.child(this.status(t, tab.status, true)));
  }

  // Folded sub-agent count, time in this state, and status, at a row's end.
  tail(el, a, subs, open, t, now) {
    const when = this.changed[a.address]?.at;
    const kids = urgent(subs.map((s) => kidStatus(s.k, this.listed)));
    return el
      .when(!open && subs.length > 0, (el) => el.child(div().flex_none().text_size(ts(11)).text_color(t[kids] ?? t.dim).child(String(subs.length))))
      .when(Boolean(when), (el) => el.child(div().flex_none().text_size(ts(11)).text_color(t.dim).child(duration(now - when))))
      .child(this.status(t, a.status));
  }

  agentRow(s, tab, label, a, subs, t, now) {
    const open = !this.folded.has(a.address);
    const quiet = a.status === "idle" && !a.focused;
    const { name, detail } = agentLabel(a, label);
    const row = this.grab(this.drop(this.row(`ag-${a.address}`, 2, t), s, tab, t), a)
      .when(a.focused, (el) => el.bg(t.raised))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", () => this.menu({ tab: "pane", target: { pane: a.pane, terminal: a.address } }))
      .child(subs.length ? this.chevron(a.address, open, t) : div().w(14).flex_none())
      .child(icon(a.program, 14, t.foreground))
      .child(h_flex().flex_1().min_w(0).gap(5).items_center()
        .child(div().flex_none().text_color(quiet ? t.muted : t.foreground).child(name))
        .when(Boolean(detail), (el) => el.child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(detail))));
    return this.tail(row, a, subs, open, t, now);
  }

  // A tab with one agent gets one row for both: the agent's icon when it is the only pane, else a folder.
  soloRow(s, tab, label, a, subs, t, now) {
    const open = !this.folded.has(a.address);
    const shown = s.active && tab.active;
    const row = this.grab(this.drop(this.row(`tb-${tab.id}`, 1, t), s, tab, t), a)
      .when(shown, (el) => el.bg(t.selected))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", () => this.menu({ tab: "tab", target: { id: tab.id, space: s.id } }))
      .child(subs.length ? this.chevron(a.address, open, t) : div().w(14).flex_none())
      .child(tab.panes === 1 ? icon(a.program, 14, t.foreground) : svg(`${ICONS}/folder.svg`).size(13).flex_none().text_color(shown ? t.accent : t.dim))
      .child(div().flex_1().min_w(0).truncate().text_color(shown ? t.foreground : t.muted).child(label));
    return this.tail(row, a, subs, open, t, now);
  }

  subRow({ k, depth }, t, level) {
    return this.row(`sub-${k.address}`, level + depth, t)
      .on_click(() => run("terminal.peek", { terminal: k.address }))
      .child(icon(k.program, 13, t.muted))
      .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(k.name || k.template || k.program?.name || k.address))
      .child(this.status(t, kidStatus(k, this.listed), true));
  }

  machineRow(on, t) {
    return h_flex().id(`m-${on ?? "local"}`).h(26).flex_none().pl(6).pr(2).pt(4).gap(6).items_center().text_size(ts(11)).text_color(t.dim)
      .child(svg(`${ICONS}/${on ? "server" : "monitor"}.svg`).size(12).flex_none())
      .child(div().flex_1().min_w(0).truncate().child(on ?? "This computer"))
      .child(div().id(`m-new-${on ?? "local"}`).size(22).flex_none().flex().items_center().justify_center().rounded(5)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .tooltip(`New space on ${on ?? "this computer"}`)
        .on_click(() => run("space.new", { machine: on ?? "" }))
        .child(svg(`${ICONS}/plus.svg`).size(12)));
  }

  // Under a header per machine once another one is connected, so each gets its own new-space button.
  rows(sp, remote, byTab, all, ps, t, now) {
    const out = [];
    for (const on of [null, ...remote]) {
      if (remote.length) out.push(this.machineRow(on, t));
      for (const s of sp.filter((s) => (s.machine ?? null) === on)) this.spaceRows(s, byTab, all, ps, t, now, out);
    }
    return out;
  }

  spaceRows(s, byTab, all, ps, t, now, out) {
    out.push(this.spaceRow(s, t));
    if (this.folded.has(s.id)) return;
    for (const tab of s.tabs) {
      const mine = byTab.get(tab.id) ?? [];
      const label = tabName(tab, lead(tab, ps));
      // Agents nest under their tab only when it has two or more.
      if (mine.length === 1) {
        const subs = this.tree(all, mine[0].address);
        out.push(this.soloRow(s, tab, label, mine[0], subs, t, now));
        if (!this.folded.has(mine[0].address)) out.push(...subs.map((sub) => this.subRow(sub, t, 2)));
        continue;
      }
      out.push(this.tabRow(s, tab, label, mine.length > 1, t));
      if (this.folded.has(tab.id)) continue;
      for (const a of mine) {
        const subs = this.tree(all, a.address);
        out.push(this.agentRow(s, tab, label, a, subs, t, now));
        if (!this.folded.has(a.address)) out.push(...subs.map((sub) => this.subRow(sub, t, 3)));
      }
    }
  }

  compact(s, i, t) {
    return h_flex().id(`sp-${s.id}`).h(26).flex_none().justify_center().gap(4)
      .when(s.active, (el) => el.bg(t.raised))
      .hover((el) => el.bg(t.hover))
      .on_click(() => run("space.select", { id: s.id }))
      .child(div().text_color(s.active ? t.foreground : t.muted).child(String(i + 1)))
      .child(div().text_color(t[s.status] ?? t.unknown).child(s.status === "blocked" || s.status === "done" ? "\u25cf" : "\u00b7"));
  }

  render() {
    const t = theme();
    fixed = props()?.size ?? null;
    const font = props()?.font;
    const collapsed = narrow();
    const sp = spaces();
    followSpace(sp, props()?.follow);
    this.paint(sp);
    const list = agents();
    this.listed = new Map(list.map((a) => [a.address, a.status]));
    const now = Date.now();
    this.track(list, now);
    const byTab = new Map();
    for (const a of list) byTab.set(a.tab, [...(byTab.get(a.tab) ?? []), a]);
    setAgentOrder(sp.flatMap((s) => s.tabs.flatMap((tab) => (byTab.get(tab.id) ?? []).map((a) => a.address))));
    const live = machines().filter((m) => m.layout !== "unavailable").map((m) => m.name);
    const remote = [...new Set([...live, ...sp.map((s) => s.machine)].filter(Boolean))].sort();
    const body = collapsed
      ? sp.map((s, i) => this.compact(s, i, t))
      : sp.length || remote.length
        ? this.rows(sp, remote, byTab, terminals(), panes(), t, now)
        : [div().px(8).h(28).text_color(t.dim).child("Loading\u2026")];
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(ts(13))
      .when(Boolean(font), (el) => el.font_family(font))
      .when(!collapsed, (el) => el.child(h_flex().h(31).flex_none().pl(16).pr(10).items_center().justify_between().text_size(ts(11.5)).text_color(t.dim)
        .child("Spaces")
        .when(!remote.length, (el) => el.child(div().id("space-new").size(26).flex_none().flex().items_center().justify_center().rounded(6)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click(() => run("space.new"))
          .child(svg(`${ICONS}/plus.svg`).size(14))))))
      .child(v_flex().id("tree").flex_1().min_h(0).px(collapsed ? 0 : 8).pb(14).overflow_y_scrollbar().mode("always")
        .on_mouse_up("left", (_e, cx) => this.letGo(cx))
        .on_hover((on, cx) => {
          if (!on) this.letGo(cx);
        })
        .children(body))
      .when(collapsed, (el) => el.child(h_flex().h(28).flex_none().items_center().justify_center()
        .child(div().id("expand").text_color(t.dim).hover((s) => s.text_color(t.foreground)).on_click(toggleSidebar).child("\u00bb"))));
  }
}
