// The page the focused agent showed (pi show_ui, Claude herdr-show), in the right sidebar:
// documents, images, tables and status cards. The agent writes them per herdr-core terminal.
import { View, div, image } from "gpui-kit";
import { h_flex, v_flex, TextView } from "gpui-base";
import { exec, focused, home, layout, notify, props, run, setShared, shared, spaces, terminals, theme } from "herdr";
import { ago, openUrl } from "./util.js";
import { safeUrl } from "./safe.js";
import { SAMPLE } from "./sample.js";

const POLL_MS = 2000;
const READ = 'cat "${XDG_STATE_HOME:-$HOME/.local/state}/pi-ui/$0.json" 2>/dev/null';

// image() only loads files under the app folder, so a page's images are copied there from the
// session's machine. The names come from the pi extension and are checked before they get here.
const IMAGES = "data/canvas";
const IMAGE_NAME = /^[A-Za-z0-9._-]+$/;
const FETCH = `
dir="$1"; machine="$2"; hc="$3"; shift 3
mkdir -p "$dir"
find "$dir" -type f -mtime +1 -delete 2>/dev/null
status=0
for name in "$@"; do
  [ -s "$dir/$name" ] && continue
  tmp="$dir/$name.tmp.$$"
  # Nothing is renamed into place unless every step before it succeeded.
  if [ -n "$machine" ]; then
    "$hc" exec --on "$machine" -- sh -c 'base64 < "\${XDG_STATE_HOME:-$HOME/.local/state}/pi-ui/$0"' "$name" > "$tmp.b64" \\
      && base64 -d < "$tmp.b64" > "$tmp"
  else
    cp "\${XDG_STATE_HOME:-$HOME/.local/state}/pi-ui/$name" "$tmp"
  fi && [ -s "$tmp" ] && mv "$tmp" "$dir/$name" || status=1
  rm -f "$tmp" "$tmp.b64"
done
exit $status
`;

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

// Whether each visited space has the canvas open, by space id.
const OPEN = "canvas.open";

function canvasShown() {
  const column = find(layout(), "canvas");
  return Boolean(column) && !column.hidden;
}

// An invisible copy that is always running, so the canvas opens even before it was ever shown:
// a new show_ui from the focused terminal shows it. The hidden canvas copy cannot do this, since
// a block's mod starts only when it first shows.
// The canvas column belongs to the whole window, so this copy also shows and hides it as the
// focused space changes: each space keeps the canvas as it was left there, and a space that
// never had it starts closed.
class Watch {
  constructor(cx) {
    this.seen = uiLabels();
    this.space = undefined;
    this.pending = null;
    cx.timer.every(1000, () => this.tick());
  }

  sync() {
    const space = focused()?.space ?? null;
    if (!space) return;
    const shown = canvasShown();
    const open = shared(OPEN) ?? {};
    if (space !== this.space) {
      const first = this.space === undefined;
      this.space = space;
      this.pending = null;
      // At startup a space with nothing saved keeps what the layout shows.
      if (!(first && !(space in open))) {
        const want = Boolean(open[space]);
        if (want !== shown) {
          this.pending = { want, until: Date.now() + 1000 };
          run(want ? "layout.show" : "layout.hide", { id: "canvas" });
          return;
        }
      }
    }
    // Until the restore lands, or something else won, the old state is not a choice.
    if (this.pending) {
      if (this.pending.want !== shown && Date.now() < this.pending.until) return;
      this.pending = null;
    }
    if (open[space] === shown) return;
    setShared(OPEN, { ...open, [space]: shown });
  }

  tick() {
    this.sync();
    const now = uiLabels();
    const address = focused()?.terminal;
    const value = address ? now.get(address) : null;
    if (value && value !== (this.seen.get(address) ?? null) && !canvasShown()) {
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
      let data = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {}
      const names = [];
      for (const b of data?.blocks ?? []) if (b.type === "image" && IMAGE_NAME.test(b.file ?? "")) names.push(b.file);
      let copied = true;
      if (names.length) {
        // One transfer at a time: a poll that arrives during a slow copy waits for the next one.
        if (this.fetching) return;
        this.fetching = true;
        const dir = `${home()}/.config/herdr-app/${IMAGES}`;
        const machine = address ? locate(address).machine : null;
        const r = await exec("sh", ["-c", FETCH, "sh", dir, machine ?? "", props()?.hc ?? "hc", ...names], { timeout: 60000 })
          .catch(() => ({ code: 1 }));
        this.fetching = false;
        copied = r.code === 0;
      }
      this.address = address;
      // A page whose images did not all arrive counts as unseen, so the next poll tries again.
      this.text = copied ? text : null;
      this.data = data;
      cx.notify();
    });
  }

  // Only https links open.
  open(link) {
    const url = safeUrl(link);
    if (url) openUrl(url.href);
    else notify({ title: "Link blocked", body: "Only https links open.", level: "error" });
  }

  block(t, b, i) {
    const key = `b${i}`;
    switch (b.type) {
      case "heading":
        return div().text_size(15).font_semibold().child(b.text ?? "");
      case "markdown":
        // Its links go through the same https check as a link button.
        return TextView.markdown(key, b.text ?? "").selectable(true).on_link_click((url) => this.open(url));
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
      case "image": {
        const ok = IMAGE_NAME.test(b.file ?? "");
        // An image element is a square unless it is told its height.
        const width = Math.max(0, (this.width ?? 440) - 20);
        const sized = b.width > 0 && b.height > 0;
        const picture = ok && image(`${IMAGES}/${b.file}`).w(width).h(sized ? (width * b.height) / b.width : width);
        return v_flex().gap(4)
          .child(ok ? picture : div().text_color(t.blocked).child("This image could not be shown."))
          .when(Boolean(b.text), (el) => el.child(div().text_size(12).text_color(t.muted).child(b.text)));
      }
      default:
        return div().text_color(t.dim).child(`Unknown block: ${b.type}`);
    }
  }

  render(_cx) {
    if (this.watch) {
      // A space switch re-renders this copy, which is sooner than its next tick.
      this.watch.sync();
      return div();
    }
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
        .child(div().child("Ask the agent to show something here, for example: show me that design doc beside the session."));
    return v_flex().id("canvas-root").size_full().py(6).gap(8).bg(t.chrome).text_color(t.foreground)
      .on_size_change((size, cx) => {
        if (size.width === this.width) return;
        this.width = size.width;
        cx.notify();
      })
      .child(header)
      .child(body)
      .when(!this.data || this.sample, (el) => el.child(toggle(this.sample ? "Hide the sample" : "Show a sample")));
  }
}
