// A telescope-style picker over every pane: type to filter, see the chosen pane's screen beside
// the list, Enter goes to it. Up/Down or ctrl-p/ctrl-n move, ctrl-u/ctrl-d scroll the screen,
// Esc leaves. Opened by mod.open:pane-picker.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { closeOverlay, focused, hc, home, panes, props, run, settings, spaces, theme } from "herdr";
import { rank } from "./fuzzy.js";

const ROW = 26;
// A popup is as tall as its content up to the height in mod.json, so this asks for all of it.
const TALL = 10000;
const REFRESH_MS = 1000;
const SPINNER = "mods/workspace-chrome/spinner.svg";

// Pi marks its titles with a letter and a dash, which says nothing in a list.
const unmarked = (title) => (title ?? "").replace(/^\S\s+-\s+/u, "").trim();

function short(path) {
  const h = home();
  return path === h || path?.startsWith(`${h}/`) ? `~${path.slice(h.length)}` : (path ?? "");
}

// Every pane in sidebar order, with the columns a query is matched against.
function entries() {
  const byTab = new Map();
  for (const p of panes()) byTab.set(p.tab, [...(byTab.get(p.tab) ?? []), p]);
  return spaces().flatMap((space) =>
    space.tabs.flatMap((tab) =>
      (byTab.get(tab.id) ?? []).map((p) => {
        const columns = [
          `${space.name} / ${tab.name}`,
          [p.name, unmarked(p.title) || p.mod].filter(Boolean).join(" · "),
          p.terminal ? (p.program?.name ?? "") : "mod",
          short(p.cwd),
        ];
        return { pane: p.pane, terminal: p.terminal, status: p.status, columns };
      }),
    ),
  );
}

// Whole steps of `unit` px that a wheel has turned, keeping the rest for its next event.
function steps(wheel, delta, unit) {
  wheel.rest = (wheel.rest ?? 0) + delta;
  const whole = Math.trunc(wheel.rest / unit);
  wheel.rest -= whole * unit;
  return whole;
}

export default class PanePicker extends View {
  init(_props, cx) {
    this.pick = focused()?.pane ?? null;
    this.at = 0;
    this.top = 0;
    this.up = 0;
    this.wheels = { list: {}, screen: {} };
    this.screens = new Map();
    this.reading = new Set();
    this.input = InputState.new({ placeholder: "Find a pane" });
    this.input.on("change", (_e, cx) => {
      this.pick = null;
      this.at = 0;
      this.select(0, cx);
    });
    this.input.on("submit", () => this.go(this.chosen()));
    this.input.focus();
    // Focused again once the popup is up, as the shipped picker does.
    cx.timer.after(600, () => this.input.focus());
    this.handle = cx.focus_handle();
    cx.timer.every(REFRESH_MS, (cx) => this.read(cx));
    this.read(cx);
  }

  rows() {
    return rank(this.input.value(), entries(), (e) => e.columns).map(({ item, hits }) => ({ ...item, hits }));
  }

  // The chosen row stays chosen while panes come and go around it.
  index(rows) {
    const at = rows.findIndex((r) => r.pane === this.pick);
    return at >= 0 ? at : Math.max(0, Math.min(this.at, rows.length - 1));
  }

  chosen() {
    const rows = this.rows();
    return rows[this.index(rows)];
  }

  select(by, cx) {
    const rows = this.rows();
    if (rows.length) {
      this.at = (this.index(rows) + by + rows.length) % rows.length;
      this.pick = rows[this.at].pane;
    }
    this.up = 0;
    this.read(cx);
    cx.notify();
  }

  // Only the screen is read: asking for history makes the core scroll a full-screen program.
  read(cx) {
    const address = this.chosen()?.terminal;
    if (!address || this.reading.has(address)) return;
    this.reading.add(address);
    cx.spawn(async (cx) => {
      let screen;
      try {
        const r = await hc(["read", address, "--json"]);
        screen = r.code === 0 ? JSON.parse(r.stdout).text.trimEnd() : r.stderr.trim();
      } catch (e) {
        screen = String(e);
      }
      this.reading.delete(address);
      if (this.screens.get(address) === screen) return;
      this.screens.set(address, screen);
      cx.notify();
    });
  }

  go(row) {
    if (!row) return;
    this.close();
    run("pane.focus", { pane: row.pane });
  }

  close() {
    closeOverlay(props()?.overlay);
  }

  glyph(t, status) {
    if (status === "working") return svg(SPINNER).size(12).flex_none().text_color(t.working).spin(900);
    return div().w(12).flex_none().text_color(t[status] ?? t.dim).child(status === "idle" ? "○" : status ? "●" : "·");
  }

  // A column's text with its matched characters in the accent color.
  marked(text, hits, t) {
    if (!hits.size) return div().truncate().child(text);
    const runs = [];
    [...text].forEach((c, i) => {
      const hit = hits.has(i);
      const last = runs[runs.length - 1];
      if (last?.hit === hit) last.text += c;
      else runs.push({ hit, text: c });
    });
    return h_flex()
      .overflow_hidden()
      .children(runs.map((r) => div().flex_none().whitespace_nowrap().when(r.hit, (el) => el.text_color(t.accent)).child(r.text)));
  }

  row(r, chosen, t) {
    const [where, label, program] = r.columns.map((text, i) => this.marked(text, r.hits[i], t));
    return h_flex()
      .id(`pp-${r.pane}`)
      .h(ROW)
      .flex_none()
      .px(8)
      .gap(10)
      .items_center()
      .rounded(5)
      .cursor_pointer()
      .when(chosen, (el) => el.bg(t.selected))
      .hover((s) => s.bg(t.hover))
      .on_click(() => this.go(r))
      .child(this.glyph(t, r.status))
      .child(where.w_2_5().min_w(0).flex_none().text_color(chosen ? t.foreground : t.muted))
      .child(label.flex_1().min_w(0).text_color(t.foreground))
      .child(program.flex_none().text_color(t.dim));
  }

  preview(r, t, lineHeight) {
    const screen = r?.terminal ? this.screens.get(r.terminal) : null;
    const lines = screen ? screen.split("\n") : [];
    const fits = Math.max(1, Math.floor((this.previewHeight ?? 400) / lineHeight));
    this.up = Math.max(0, Math.min(this.up, lines.length - fits));
    const end = lines.length - this.up;
    return v_flex()
      .flex_1()
      .min_w(0)
      .h_full()
      .pl(12)
      .gap(6)
      .border_l(1)
      .border_color(t.border)
      .child(
        h_flex()
          .h(ROW)
          .flex_none()
          .gap(10)
          .text_color(t.dim)
          .child(div().flex_none().text_color(t.muted).child(r?.terminal ?? r?.columns[2] ?? ""))
          .when(Boolean(r), (el) => el.child(this.marked(r.columns[3], r.hits[3], t).flex_1().min_w(0))),
      )
      .child(
        v_flex()
          .id("pp-screen")
          .flex_1()
          .min_h(0)
          .overflow_hidden()
          .text_color(t.foreground)
          .on_size_change((size, cx) => {
            this.previewHeight = size.height / (settings().zoom ?? 1);
            cx.notify();
          })
          .on_scroll_wheel((e, cx) => {
            this.up += steps(this.wheels.screen, e.delta.y, lineHeight);
            cx.notify();
          })
          .when(Boolean(r) && !r.terminal, (el) => el.child(div().text_color(t.dim).child("A mod pane has no screen.")))
          .children(lines.slice(Math.max(0, end - fits), end).map((line) => div().h(lineHeight).flex_none().whitespace_nowrap().child(line))),
      );
  }

  render() {
    const t = theme();
    const look = settings();
    const size = look.font_size ?? 14;
    const lineHeight = Math.round(size * 1.2);
    const rows = this.rows();
    const at = this.index(rows);
    const chosen = rows[at];
    const fits = Math.max(1, Math.floor((this.listHeight ?? 400) / ROW));
    this.top = Math.max(0, Math.min(this.top, rows.length - fits));
    if (at < this.top) this.top = at;
    if (at >= this.top + fits) this.top = at - fits + 1;

    return h_flex()
      .id("pane-picker")
      .track_focus(this.handle)
      .w_full()
      .h(TALL)
      .p(14)
      .gap(12)
      .bg(t.popover)
      .text_size(size)
      .when(Boolean(look.font_family), (el) => el.font_family(look.font_family))
      .on_key_down((e, cx) => {
        const { control } = e.modifiers;
        const half = Math.max(1, Math.floor((this.previewHeight ?? 400) / lineHeight / 2));
        if (e.key === "escape") return this.close();
        if (e.key === "down" || (control && e.key === "n")) this.select(1, cx);
        else if (e.key === "up" || (control && e.key === "p")) this.select(-1, cx);
        else if (control && e.key === "u") this.up += half;
        else if (control && e.key === "d") this.up -= half;
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .child(
        v_flex()
          .w_2_5()
          .flex_none()
          .min_w(0)
          .h_full()
          .gap(8)
          .child(
            h_flex()
              .h(34)
              .flex_none()
              .px(10)
              .gap(8)
              .items_center()
              .rounded(7)
              .border_1()
              .border_color(t.accent)
              .bg(t.background)
              .child(div().flex_none().text_color(t.accent).child(">"))
              .child(Input.new(this.input).flex_1().h_full().text_size(size).text_color(t.foreground))
              .child(div().flex_none().text_color(t.dim).child(`${rows.length ? at + 1 : 0}/${rows.length}`)),
          )
          .child(
            v_flex()
              .id("pp-list")
              .flex_1()
              .min_h(0)
              .overflow_hidden()
              .on_size_change((size, cx) => {
                this.listHeight = size.height / (settings().zoom ?? 1);
                cx.notify();
              })
              .on_scroll_wheel((e, cx) => {
                this.top = Math.max(0, Math.min(this.top - steps(this.wheels.list, e.delta.y, ROW), rows.length - fits));
                // The choice follows the wheel, so the next frame does not scroll back to it.
                this.select(Math.max(this.top, Math.min(at, this.top + fits - 1)) - at, cx);
              })
              .children(rows.slice(this.top, this.top + fits).map((r) => this.row(r, r === chosen, t))),
          ),
      )
      .child(this.preview(chosen, t, lineHeight));
  }
}
