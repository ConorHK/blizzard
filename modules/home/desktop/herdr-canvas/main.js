// Generative UI: the cards, tables and buttons that the focused pi session drew with its show_ui
// tool, in the right sidebar. Its pi extension writes them per herdr-core terminal.
import { View, div } from "gpui-kit";
import { h_flex, v_flex, TextView } from "gpui-base";
import { exec, focused, hc, layout, notify, props, run, spaces, terminals, theme } from "herdr";
import { ago, openUrl } from "./util.js";
import { effect, MAX_SEND, safeUrl } from "./safe.js";
import { SAMPLE } from "./sample.js";

const POLL_MS = 2000;
const READ = 'cat "${XDG_STATE_HOME:-$HOME/.local/state}/pi-ui/$0.json" 2>/dev/null';

// "host/t9" lives on host as t9; "t2" lives here.
function locate(address) {
  const i = address.lastIndexOf("/");
  return i < 0 ? { machine: null, id: address } : { machine: address.slice(0, i), id: address.slice(i + 1) };
}

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// "Control Plane / 1": the focused space and tab, as the agents list names them.
function where() {
  const f = focused();
  for (const sp of spaces()) {
    if (sp.id !== f?.space) continue;
    for (const tab of sp.tabs) if (tab.id === f.tab) return `${sp.name} / ${tab.name}`;
    return sp.name;
  }
  return "";
}

// The pi.ui label that show_ui sets on its terminal, by address.
function uiLabels() {
  const out = new Map();
  for (const t of terminals()) out.set(t.address, t.labels?.["pi.ui"] ?? null);
  return out;
}

// An invisible copy that is always running, so the canvas opens even before it was ever shown:
// a new show_ui from the focused terminal shows it. The hidden canvas copy cannot do this, since
// a block's mod starts only when it first shows.
class Watch {
  constructor(cx) {
    this.seen = uiLabels();
    cx.timer.every(1000, () => this.tick());
  }

  tick() {
    const now = uiLabels();
    const address = focused()?.terminal;
    const value = address ? now.get(address) : null;
    if (value && value !== (this.seen.get(address) ?? null) && find(layout(), "canvas")?.hidden) {
      run("layout.show", { id: "canvas" });
    }
    this.seen = now;
  }
}

function toneColor(t, tone) {
  return { good: t.done, bad: t.blocked, warn: t.working, info: t.accent, muted: t.muted }[tone] ?? t.foreground;
}

export default class Canvas extends View {
  init(_props, cx) {
    if (props()?.role === "watch") {
      this.watch = new Watch(cx);
      return;
    }
    this.address = null;
    this.text = null;
    this.data = null;
    this.sample = false;
    this.refresh(cx);
    cx.timer.every(POLL_MS, (cx) => this.refresh(cx));
  }

  refresh(cx) {
    // A hidden copy keeps its timer, so it skips the read on the other machine.
    if (find(layout(), "canvas")?.hidden) return;
    const address = focused()?.terminal ?? null;
    cx.spawn(async (cx) => {
      let text = "";
      if (address) {
        const { machine, id } = locate(address);
        const r = await exec("sh", ["-c", READ, id], { on: machine }).catch(() => ({ stdout: "" }));
        text = r.stdout;
      }
      if (address === this.address && text === this.text) return;
      if (address !== this.address) this.sample = false;
      this.address = address;
      this.text = text;
      try {
        this.data = text ? JSON.parse(text) : null;
      } catch {
        this.data = null;
      }
      cx.notify();
    });
  }

  // A send button types into the session as the user; the sample only says what it would send.
  press(item) {
    if (item.link) {
      const url = safeUrl(item.link);
      if (url) openUrl(url.href);
      else notify({ title: "Link blocked", body: "Only https links open.", level: "error" });
      return;
    }
    if (typeof item.send !== "string" || item.send.length > MAX_SEND) return;
    if (this.sample || !this.address) {
      notify({ title: "Sample button", body: `Would send: ${item.send}`, level: "info", timeout: 3000 });
      return;
    }
    hc(["send", this.address, item.send]).then((r) => {
      if (r.code !== 0) notify({ title: "Not sent", body: (r.stderr || r.stdout).trim(), level: "error" });
    });
  }

  block(t, b, i) {
    const key = `b${i}`;
    switch (b.type) {
      case "heading":
        return div().text_size(15).font_semibold().child(b.text ?? "");
      case "markdown":
        // Its links go through the same https check as a link button.
        return TextView.markdown(key, b.text ?? "").selectable(true).on_link_click((url) => this.press({ link: url }));
      case "code":
        return TextView.markdown(key, `\`\`\`${b.language ?? ""}\n${b.text ?? ""}\n\`\`\``).selectable(true);
      case "stats": {
        const tiles = [];
        for (const s of b.items ?? []) {
          tiles.push(v_flex().px(10).py(6).gap(2).border(1).border_color(t.border).bg(t.background)
            .child(div().text_size(20).text_color(toneColor(t, s.tone)).child(s.value ?? ""))
            .child(div().text_size(11).text_color(t.muted).child(s.label ?? "")));
        }
        return div().flex().flex_wrap().gap(6).children(tiles);
      }
      case "progress": {
        const v = Math.max(0, Math.min(1, Number(b.value) || 0));
        return v_flex().gap(4)
          .child(h_flex().justify_between().text_size(12)
            .child(div().text_color(t.muted).child(b.label ?? ""))
            .child(div().text_color(t.foreground).child(`${Math.round(v * 100)}%`)))
          .child(h_flex().h(6).bg(t.border)
            .child(div().h_full().flex_grow(v).bg(toneColor(t, b.tone ?? "info")))
            .child(div().h_full().flex_grow(1 - v)));
      }
      case "table": {
        const cell = (text, head) => div().flex_1().w_0().truncate().text_color(head ? t.muted : t.foreground).child(String(text ?? ""));
        const row = (cells, head, n) => {
          const out = [];
          for (const c of cells) out.push(cell(c, head));
          return h_flex().id(`${key}-r${n}`).px(6).py(3).gap(8).text_size(12)
            .when(!head, (el) => el.border_t_1().border_color(t.border))
            .children(out);
        };
        const rows = [row(b.columns ?? [], true, "h")];
        let n = 0;
        for (const r of b.rows ?? []) rows.push(row(r, false, n++));
        return v_flex().border(1).border_color(t.border).bg(t.background).children(rows);
      }
      case "list": {
        const rows = [];
        let n = 0;
        for (const it of b.items ?? []) {
          const url = it.link ? safeUrl(it.link) : null;
          rows.push(h_flex().id(`${key}-i${n++}`).px(6).py(4).gap(8).items_center().text_size(13)
            .when(Boolean(url), (el) => el.hover((s) => s.bg(t.hover)).on_click(() => openUrl(url.href)))
            .child(div().w(6).h(6).bg(toneColor(t, it.tone ?? "muted")))
            .child(div().text_color(url ? t.accent : t.foreground).child(it.text ?? ""))
            .child(div().flex_1().truncate().text_color(t.dim).child(it.detail ?? ""))
            // The host is drawn by the canvas, not taken from the agent's text.
            .when(Boolean(url), (el) => el.child(div().text_size(11).text_color(t.dim).child(url.host)))
            .when(Boolean(it.link) && !url, (el) => el.child(div().text_size(11).text_color(t.blocked).child("link blocked"))));
        }
        return v_flex().children(rows);
      }
      case "buttons": {
        const buttons = [];
        let n = 0;
        for (const it of b.items ?? []) {
          const fx = effect(it);
          const color = fx.ok ? toneColor(t, it.tone ?? "info") : t.dim;
          // A button always shows what it does, so a friendly label cannot hide what it sends or opens.
          buttons.push(v_flex().id(`${key}-btn${n++}`).px(10).py(4).border(1).border_color(color)
            .text_size(13).when(fx.ok, (el) => el.hover((s) => s.bg(t.hover)).on_click(() => this.press(it)))
            .child(div().text_color(color).child(it.label ?? ""))
            .child(div().max_w(380).truncate().text_size(11).text_color(fx.ok ? t.dim : t.blocked).child(fx.text)));
        }
        return div().flex().flex_wrap().gap(6).children(buttons);
      }
      default:
        return div().text_color(t.dim).child(`Unknown block: ${b.type}`);
    }
  }

  render(_cx) {
    if (this.watch) return div();
    const t = theme();
    const data = this.sample ? SAMPLE : this.data;
    const blocks = [];
    let i = 0;
    for (const b of data?.blocks ?? []) blocks.push(this.block(t, b, i++));
    const header = h_flex().h(28).px(10).gap(8).items_center().text_size(13)
      .child(div().font_semibold().truncate().child(data?.title ?? "Canvas"))
      .child(div().flex_1().truncate().text_color(t.dim).child(data ? `${where()} · ${ago(data.updated)}` : where()))
      .child(div().id("canvas-close").px(6).text_color(t.muted).hover((s) => s.text_color(t.foreground))
        .on_click(() => run("layout.hide", { id: "canvas" })).child("×"));
    const toggle = (label) => div().id("canvas-sample").px(10).text_size(12).text_color(t.accent)
      .hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => {
        this.sample = !this.sample;
        cx.notify();
      })
      .child(label);
    const body = data
      ? v_flex().id("canvas-blocks").flex_1().min_h(0).px(10).gap(10).overflow_y_scrollbar().children(blocks)
      : v_flex().px(10).gap(8).text_size(13).text_color(t.dim)
        .child(div().child(this.address ? "This session has not drawn anything yet." : "Focus a terminal."))
        .child(div().child("Ask pi to use its show_ui tool, for example: show me a status board of this work."));
    return v_flex().size_full().py(6).gap(8).bg(t.chrome).text_color(t.foreground)
      .child(header)
      .child(body)
      .when(!this.data || this.sample, (el) => el.child(toggle(this.sample ? "Hide the sample" : "Show a sample")));
  }
}
