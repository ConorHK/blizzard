// A telescope-style picker over every pane. ctrl-t lists the panes by name, ctrl-g greps the
// text on their screens and in their history. The chosen pane's screen shows beside the list in
// its own colors, and Enter goes to it. Up/Down or ctrl-p/ctrl-n move, ctrl-u/ctrl-d scroll the
// screen, Esc leaves. Opened by mod.open:pane-picker.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { closeOverlay, exec, focused, hc, home, panes, props, run, settings, spaces, terminals, theme } from "herdr";
import { rank } from "./fuzzy.js";
import { excerpt, pattern, search } from "./grep.js";
import { SCREENS } from "./tools.js";

const ROW = 26;
// A popup is as tall as its content up to the height in mod.json, so this asks for all of it.
const TALL = 10000;
const REFRESH_MS = 1000;
// How often a grep reads every pane again, so that new output and new panes are searched.
const SWEEP_MS = 3000;
// Lines read above each screen, for grep to search and the preview to scroll back through.
const HISTORY = 300;
// The most rows a grep lists.
const MOST = 500;
// Terminals per run of the helper, which keeps each answer well under what exec returns.
const BATCH = 10;
const SPINNER = "mods/workspace-chrome/spinner.svg";

// Pi marks its titles with a letter and a dash, which says nothing in a list.
const unmarked = (title) => (title ?? "").replace(/^\S\s+-\s+/u, "").trim();

function short(path) {
  const h = home();
  return path === h || path?.startsWith(`${h}/`) ? `~${path.slice(h.length)}` : (path ?? "");
}

// Every pane in sidebar order, with the columns a name query is matched against.
function entries() {
  const byTab = new Map();
  for (const p of panes()) byTab.set(p.tab, [...(byTab.get(p.tab) ?? []), p]);
  return spaces().flatMap((space) =>
    space.tabs.flatMap((tab) =>
      (byTab.get(tab.id) ?? []).map((p) => {
        const columns = [
          `${space.name} / ${tab.name}`,
          [p.name, unmarked(p.title) || p.mod].filter(Boolean).join(": "),
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

// Text as a screen with no styles.
function unstyled(text) {
  const texts = text.split("\n");
  return { raw: text, screen: 0, styles: [{}], lines: texts.map((line) => (line ? [[line, 0]] : [])), texts };
}

// Terminals' histories and screens as the core paints them, in lines of [text, style] runs.
// hc attach wants a tty, and splitting 30 paints takes longer than the half second a mod's turn
// may run, so a helper does both for a batch at once.
async function painted(addresses) {
  const read = new Map();
  try {
    const r = await exec(SCREENS, ["--history", String(HISTORY), ...addresses], { timeout: 10000 });
    for (const raw of r.stdout.split("\n").filter(Boolean)) {
      const screen = JSON.parse(raw);
      if (screen.error === undefined) read.set(screen.terminal, { raw, ...screen });
    }
  } catch {
    // Whatever the helper could not paint is read as text.
  }
  return read;
}

// A terminal's screen as text. Only the screen: asking hc read for history makes the core
// scroll a full-screen program.
async function unpainted(address) {
  try {
    const r = await hc(["read", address, "--json"]);
    return unstyled(r.code === 0 ? JSON.parse(r.stdout).text.trimEnd() : r.stderr.trim());
  } catch (e) {
    return unstyled(String(e));
  }
}

// Every terminal's screen by address: in its colors where the helper can paint it, as text
// where it cannot.
async function fetchScreens(addresses) {
  const batches = [];
  for (let i = 0; SCREENS && i < addresses.length; i += BATCH) batches.push(addresses.slice(i, i + BATCH));
  const read = new Map((await Promise.all(batches.map(painted))).flatMap((batch) => [...batch]));
  const rest = addresses.filter((address) => !read.has(address));
  (await Promise.all(rest.map(unpainted))).forEach((screen, i) => read.set(rest[i], screen));
  return read;
}

// A run's color: one of the theme's 16 by index, or the color itself.
const shade = (color, t) => (typeof color === "number" ? t[`ansi${color}`] : color);

export default class PanePicker extends View {
  init(_props, cx) {
    this.mode = "panes";
    this.pick = focused()?.pane ?? null;
    this.at = 0;
    this.top = 0;
    this.up = 0;
    this.wheels = { list: {}, screen: {} };
    this.screens = new Map();
    this.reading = new Set();
    this.stamp = 0;
    this.swept = 0;
    this.found = { key: null, rows: [] };
    this.tried = null;
    this.input = InputState.new();
    this.input.on("change", (_e, cx) => this.restart(cx));
    this.input.on("submit", () => this.go(this.chosen()));
    this.input.focus();
    // Focused again once the popup is up, as the shipped picker does.
    cx.timer.after(600, () => this.input.focus());
    this.handle = cx.focus_handle();
    cx.timer.every(REFRESH_MS, (cx) => {
      this.refresh(cx);
      this.regrep(cx);
    });
    this.refresh(cx);
  }

  rows() {
    const all = entries();
    if (this.mode === "grep") return this.found.key === this.key(all) ? this.found.rows : [];
    return rank(this.input.value(), all, (e) => e.columns).map(({ item, hits }) => ({ ...item, hits }));
  }

  // What a grep's rows come from: the query, the screens read so far, and the panes.
  key(all) {
    return [this.input.value(), this.stamp, ...all.map((e) => e.pane)].join("\n");
  }

  // One row per matching line: panes in sidebar order, each pane's newest line first. Never
  // called while drawing: the app cuts off a pattern that backtracks without end, which would
  // leave the picker undrawn, and in a turn of its own only leaves it without rows.
  grep() {
    const all = entries();
    const key = this.key(all);
    if (this.found.key === key || this.tried === key) return false;
    this.tried = key;
    const re = pattern(this.input.value());
    const rows = [];
    for (const entry of re ? all.filter((e) => e.terminal) : []) {
      const texts = this.screens.get(entry.terminal)?.texts ?? [];
      for (const hit of search(re, texts, MOST - rows.length)) {
        rows.push({ ...entry, ...hit, shown: excerpt(texts[hit.line], hit.start, hit.end) });
      }
    }
    this.found = { key, rows };
    return true;
  }

  // Greps again where the rows are stale. It comes last in a turn, as the turn may end in it.
  regrep(cx) {
    if (this.mode !== "grep" || !this.grep()) return;
    this.refresh(cx);
    cx.notify();
  }

  // A chosen pane stays chosen while panes come and go around it; a grep row goes by its place.
  index(rows) {
    const at = this.pick ? rows.findIndex((r) => r.pane === this.pick) : -1;
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
      this.pick = this.mode === "panes" ? rows[this.at].pane : null;
    }
    this.up = 0;
    this.refresh(cx);
    cx.notify();
  }

  restart(cx) {
    this.pick = null;
    this.at = 0;
    this.select(0, cx);
    this.regrep(cx);
  }

  show(mode, cx) {
    if (this.mode === mode) return;
    this.mode = mode;
    if (mode === "grep") this.sweep(cx);
    this.restart(cx);
  }

  // The chosen pane is read every second; a grep also reads them all every few.
  refresh(cx) {
    if (this.mode === "grep" && Date.now() - this.swept >= SWEEP_MS) return this.sweep(cx);
    const address = this.chosen()?.terminal;
    if (address) this.read([address], cx);
  }

  sweep(cx) {
    this.swept = Date.now();
    this.read(entries().map((e) => e.terminal).filter(Boolean), cx);
  }

  // Reads terminals into this.screens, each by one reader at a time.
  read(addresses, cx) {
    const wanted = addresses.filter((address) => !this.reading.has(address));
    if (!wanted.length) return;
    wanted.forEach((address) => this.reading.add(address));
    cx.spawn(async (cx) => {
      const read = await fetchScreens(wanted);
      wanted.forEach((address) => this.reading.delete(address));
      for (const [address, screen] of read) {
        if (this.screens.get(address)?.raw === screen.raw) continue;
        this.screens.set(address, screen);
        this.stamp++;
      }
      cx.notify();
      this.regrep(cx);
    });
  }

  go(row) {
    if (!row) return;
    this.close();
    run("pane.focus", { pane: row.pane });
    if (row.line === undefined) return;
    const screen = this.screens.get(row.terminal);
    // A match in the history is scrolled to a third of the way down the pane, counting the rows
    // that its long lines wrap onto.
    const cols = terminals().find((x) => x.address === row.terminal)?.cols || Infinity;
    const above = screen.texts.slice(row.line, screen.screen).reduce((n, text) => n + Math.max(1, Math.ceil(text.length / cols)), 0);
    if (!above) return;
    const rows = screen.lines.length - screen.screen;
    run("terminal.scroll", { terminal: row.terminal, to: "bottom" });
    run("terminal.scroll", { terminal: row.terminal, lines: -(above + Math.floor(rows / 3)) });
  }

  close() {
    closeOverlay(props()?.overlay);
  }

  glyph(t, status) {
    if (status === "working") return svg(SPINNER).size(12).flex_none().text_color(t.working).spin(900);
    const dot = div().size(8).mx(2).flex_none().rounded_full();
    if (!status) return dot;
    return status === "idle" ? dot.border_1().border_color(t.idle) : dot.bg(t[status] ?? t.dim);
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
    const where = (el) => el.min_w(0).flex_none().text_color(chosen ? t.foreground : t.muted);
    const row = h_flex()
      .id(`pp-${r.pane}-${r.line ?? ""}`)
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
      .child(this.glyph(t, r.status));
    if (r.shown) {
      const { text, start, end } = r.shown;
      const part = (text, color) => div().flex_none().whitespace_nowrap().text_color(color).child(text);
      return row
        .child(where(div().truncate().child(r.columns[0])).w_1_3())
        .child(
          h_flex()
            .flex_1()
            .min_w(0)
            .overflow_hidden()
            .children([part(text.slice(0, start), t.foreground), part(text.slice(start, end), t.accent), part(text.slice(end), t.foreground)]),
        );
    }
    const [place, label, program] = r.columns.map((text, i) => this.marked(text, r.hits[i], t));
    return row
      .child(where(place).w_2_5())
      .child(label.flex_1().min_w(0).text_color(t.foreground))
      .child(program.flex_none().text_color(t.dim));
  }

  // One line of a screen in its colors, with a grep row's match marked.
  line(runs, styles, hit, t, height) {
    const pieces = [];
    let from = 0;
    for (const [text, index] of runs) {
      const style = styles[index];
      const to = from + text.length;
      if (!hit || hit.end <= from || hit.start >= to) pieces.push({ text, style });
      else {
        const a = Math.max(hit.start, from) - from;
        const b = Math.min(hit.end, to) - from;
        pieces.push({ text: text.slice(0, a), style }, { text: text.slice(a, b), style, hit: true }, { text: text.slice(b), style });
      }
      from = to;
    }
    return h_flex()
      .h(height)
      .flex_none()
      .when(Boolean(hit), (el) => el.bg(t.hover))
      .children(pieces.filter((p) => p.text).map((p) => this.piece(p, t)));
  }

  piece({ text, style, hit }, t) {
    let fg = shade(style.fg, t);
    let bg = shade(style.bg, t);
    if (style.reverse) [fg, bg] = [bg ?? t.background, fg ?? t.foreground];
    if (hit) [fg, bg] = [t.accent_foreground, t.accent];
    return div()
      .h_full()
      .flex_none()
      .whitespace_nowrap()
      .when(Boolean(fg), (el) => el.text_color(fg))
      .when(Boolean(bg), (el) => el.bg(bg))
      .when(Boolean(style.bold), (el) => el.font_bold())
      .when(Boolean(style.italic), (el) => el.italic())
      .when(Boolean(style.underline), (el) => el.underline())
      .when(Boolean(style.strike), (el) => el.line_through())
      .when(Boolean(style.dim), (el) => el.opacity(0.6))
      .child(text);
  }

  preview(r, t, lineHeight) {
    const { lines, styles } = (r?.terminal && this.screens.get(r.terminal)) || { lines: [] };
    const fits = Math.max(1, Math.floor((this.previewHeight ?? 400) / lineHeight));
    const last = Math.max(0, lines.length - fits);
    // A grep row shows its line mid-screen, a pane the end of its screen.
    const base = r?.line === undefined ? last : r.line - Math.floor(fits / 2);
    const first = Math.max(0, Math.min(base - this.up, last));
    this.up = base - first;
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
          .when(Boolean(r), (el) => el.child(this.marked(r.columns[3], r.hits?.[3] ?? new Set(), t).flex_1().min_w(0))),
      )
      .child(
        v_flex()
          .id("pp-screen")
          .flex_1()
          .min_h(0)
          .overflow_hidden()
          .line_height(`${lineHeight}px`)
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
          .children(lines.slice(first, first + fits).map((runs, i) => this.line(runs, styles, first + i === r?.line ? r : null, t, lineHeight))),
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
    const grep = this.mode === "grep";
    const count = grep && this.reading.size > 1 ? "reading" : `${rows.length ? at + 1 : 0}/${rows.length}${grep && rows.length >= MOST ? "+" : ""}`;
    let hint = "";
    if (grep && !this.input.value()) hint = "Type to search the text of every pane.";
    else if (grep && this.tried === this.key(entries()) && this.found.key !== this.tried) hint = "This pattern took too long to match.";

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
        else if (control && e.key === "t") this.show("panes", cx);
        else if (control && e.key === "g") this.show("grep", cx);
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
              .child(div().flex_none().text_color(t.accent).child(`${this.mode} >`))
              .child(Input.new(this.input).flex_1().h_full().text_size(size).text_color(t.foreground))
              .child(div().flex_none().text_color(t.dim).child(count)),
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
              .when(Boolean(hint), (el) => el.child(div().px(8).text_color(t.dim).child(hint)))
              .children(rows.slice(this.top, this.top + fits).map((r) => this.row(r, r === chosen, t))),
          ),
      )
      .child(this.preview(chosen, t, lineHeight));
  }
}
