// The graph itself: jj log as a table (graph, change, description, date,
// author, commit) for the focused pane's repository, or `props.folder`.
// Labels take double-clicks and right-clicks (menus).
import { div, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex, Scrollbar, v_virtual_list } from "gpui-base";
import { spaces, panes, focused, exec, watchFolder, readTextFile, theme, settings, props, shared, setShared, openOverlay, closeOverlay, home, updates } from "herdr";
import { layoutLanes } from "./lanes.js";
import { READ, ALL, LABEL, logArgs, ancestorArgs, parseLog, labelsOf, hitLabel, menuFor, menuHeight, revOf,
  diffArgs, describeArgs, parseGitDiff, diffRows, jjError } from "./jj.js";
import { perform } from "./act.js";
import { icon } from "./menu.js";

function location(folder) {
  if (folder) return { cwd: folder, on: null };
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on };
}

const PAGE = 300, ROW = 24, LANE = 12, PAD = 6, DIFF_ROW = 20, CHANGE_CHARS = 8;
// Herdr 0.1.12 and later zoom a virtual list's rows and paths themselves.
const older = (a, b) => { const x = a.split(".").map(Number), y = b.split(".").map(Number); for (let i = 0; i < 3; i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) < (y[i] ?? 0); return false; };
let zoomedLists;
const listsZoom = () => zoomedLists ??= (() => { try { const v = updates()?.app?.version; return Boolean(v) && !older(v, "0.1.12"); } catch { return false; } })();
const GRAPH_MIN = 56;
const DETAIL_DEFAULT = 320, DETAIL_MIN = 120, DETAIL_ROWS = 3;
// The header (42), the toolbar (34) and the column headings (24), plus the border.
const CHROME_H = 102;
// Bounded so a hung watch or a huge history can't flood jj with ancestry lookups.
const MAX_LOOKUPS = 40;
const COLUMNS = { graph: { width: null, min: 24, side: 1 }, date: { width: 62, min: 36, max: 240, side: -1 },
  author: { width: 120, min: 50, max: 400, side: -1 }, hash: { width: 80, min: 40, max: 200, side: -1 } };
const withDefaults = (saved) => ({ ...Object.fromEntries(Object.entries(COLUMNS).map(([k, c]) => [k, c.width])), ...saved });
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const pad2 = (n) => String(n).padStart(2, "0");
const laneColors = (t) => [t.ansi4, t.ansi2, t.ansi5, t.ansi3, t.ansi6, t.ansi1, t.ansi12, t.ansi10, t.ansi13, t.ansi11, t.ansi14, t.ansi9];

function ago(seconds) {
  const s = Date.now() / 1000 - seconds;
  if (s < 60) return "now";
  if (s < 3600) return `${Math.round(s / 60)}m`;
  if (s < 86400) return `${Math.round(s / 3600)}h`;
  if (s < 86400 * 30) return `${Math.round(s / 86400)}d`;
  const d = new Date(seconds * 1000);
  return d.getFullYear() === new Date().getFullYear() ? `${MONTHS[d.getMonth()]} ${d.getDate()}` : `${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

function stamp(seconds) {
  const d = new Date(seconds * 1000);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

const tilde = (path, on) => (!on && path?.startsWith(home()) ? "~" + path.slice(home().length) : path);
const shortOf = (c) => c.prefix + c.rest;
const brief = (c) => ({ hash: c.hash, change: c.change, prefix: c.prefix, rest: c.rest, subject: c.subject, parents: c.parents,
  wc: c.wc, immutable: c.immutable, root: c.root, divergent: c.divergent });
const count = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
const DETAILS = 100;
const keep = (map, key, value, max) => { map.delete(key); map.set(key, value); if (map.size > max) map.delete(map.keys().next().value); };
// A layout with a one-size bitmap font passes that font, its size and its glyph advance.
const look = () => ({ size: props()?.size ?? null, font: props()?.font ?? null, advance: props()?.advance ?? 0.6 });

// Parents outside the shown set join their nearest shown ancestors with a
// dashed line, or end in a stub when none is shown, as `jj log` draws them.
async function connect(commits, revset, jj) {
  const shown = new Set(commits.map((c) => c.hash));
  const missing = [...new Set(commits.flatMap((c) => c.parents.filter((p) => !shown.has(p))))];
  const found = new Map();
  await Promise.all(missing.slice(0, MAX_LOOKUPS).map(async (p) => {
    const r = await jj(ancestorArgs(p, revset));
    found.set(p, r.code === 0 ? r.stdout.split("\n").filter(Boolean) : []);
  }));
  for (const c of commits) {
    if (c.parents.every((p) => shown.has(p))) continue;
    const parents = [], indirect = new Set();
    for (const p of c.parents) {
      if (shown.has(p)) { if (!parents.includes(p)) parents.push(p); continue; }
      for (const a of found.get(p) ?? []) if (!parents.includes(a)) { parents.push(a); indirect.add(a); }
    }
    c.elided = c.parents.some((p) => !shown.has(p) && !(found.get(p)?.length));
    c.parents = parents; c.indirect = indirect;
  }
  return [...found].map(([p, a]) => `${p}:${a.join(",")}`).join(" ");
}

// Everything the table shows for a folder, in one round of jj calls.
async function readFolder(cwd, on, { all, limit }) {
  const jj = (args) => exec("jj", args, { cwd, on });
  const [top, log, wc, op, remotes, config] = await Promise.all([
    jj(["root", ...READ]), jj(logArgs({ revset: all ? ALL : null, limit: limit + 1 })),
    jj(["log", ...READ, "--no-graph", "-r", "@", "-T", String.raw`change_id ++ "\0" ++ change_id.shortest(8)`]),
    jj(["op", "log", ...READ, "--no-graph", "-n", "1", "-T", "id"]),
    jj(["git", "remote", "list", ...READ]), all ? null : jj(["config", "get", "revsets.log", ...READ])]);
  if (top.code !== 0) return { state: "norepo", cwd, on };
  if (log.code !== 0) throw new Error(jjError(log));
  const parsed = parseLog(log.stdout), base = parsed.slice(0, limit);
  const revset = all ? ALL : (config?.code === 0 && config.stdout.trim()) || "@ | ancestors(immutable_heads().., 2) | trunk()";
  const ancestry = all ? "" : await connect(base, revset, jj);
  const [wcChange, wcShort] = wc.code === 0 ? wc.stdout.split("\0") : [null, null];
  return {
    root: top.stdout.trim(), on, cwd, base, limit, hasMore: parsed.length > limit,
    wcChange, wcShort, op: op.stdout.trim(),
    remoteNames: remotes.code === 0 ? remotes.stdout.split("\n").filter(Boolean).map((l) => l.split(/\s+/)[0]) : [],
    signature: [log.stdout, ancestry, wc.stdout, remotes.stdout].join("\0"), scope: String(all),
  };
}

const folderState = () => ({
  state: "loading", root: null, on: null, cwd: null, error: null,
  base: [], commits: [], rows: [], lanes: 1, labels: new Map(), index: new Map(), hasMore: false, limit: PAGE, ctx: null,
  wcChange: null, wcShort: null, op: null, remoteNames: [], signature: null, scope: null, moreAsked: null,
  selected: null, details: null, diff: null,
});

export class Graph {
  init(cx) {
    this.folder = props()?.folder ?? null;
    // A scrollbar finds its list by name: each copy needs its own.
    this.listId = `jj-rows-${Math.random().toString(36).slice(2)}`;
    this.diffId = `${this.listId}-diff`;
    this.all = false; this.remotes = true; this.wide = false; this.narrow = false; this.graphMax = 160; this.scale = null;
    this.watchToken = 0; this.seenChange = shared("jj-graph.changed");
    this.cols = withDefaults(); this.drag = null;
    this.detail = Number(shared("jj-graph.details")) || 0; this.seenDetail = this.detail;
    this.commitDetails = new Map();
    this.handle = cx.focus_handle();
    if (props()?.overlay) this.handle.focus();
    this.reset();
    this.refresh(cx);
    // Remote spaces and repositories too big to watch are read again on a timer.
    cx.timer.every(15000, (cx) => { if (this.root && (this.on || this.pollTree)) this.snapshot(cx); });
    cx.timer.every(4000, (cx) => { if (this.root && !this.on && this.pollOps) this.checkOp(cx); });
  }

  key() { return JSON.stringify(location(this.folder)); }

  reset() {
    Object.assign(this, folderState());
    this.watchToken++; this.watching = null; this.pollOps = false; this.pollTree = false;
  }

  refresh(cx) {
    const { cwd, on } = location(this.folder), context = this.key();
    if (context !== this.context) { this.context = context; this.reset(); this.loading = null; }
    if (!cwd) { this.state = "nofolder"; return; }
    const { all, limit } = this;
    if (this.loading?.key === context) { this.again = true; return; }
    const id = this.loadSeq = (this.loadSeq ?? 0) + 1;
    this.loading = { key: context, id }; this.again = false;
    const stale = () => this.loadSeq !== id || this.key() !== context;
    cx.spawn(async (cx) => {
      try {
        const read = await readFolder(cwd, on, { all, limit });
        if (stale()) return;
        if (read.state === "norepo") { this.reset(); Object.assign(this, read); return; }
        if (!on) this.watch(read.root, cx);
        const shown = this.state === "ready" || this.state === "empty";
        if (shown && read.signature === this.signature && read.scope === this.scope) { this.op = read.op; return; }
        Object.assign(this, read);
        this.build();
      } catch (e) {
        if (!stale()) { this.state = "error"; this.error = String(e?.message ?? e); }
      } finally {
        if (this.loading?.id === id) {
          this.loading = null; cx.notify();
          if (this.again) this.refresh(cx);
        }
      }
    });
  }

  build() {
    const commits = this.base.map((c) => ({ ...c }));
    const { rows, width } = layoutLanes(commits);
    this.commits = commits; this.rows = rows; this.lanes = width;
    const { advance, size } = look();
    this.labels = new Map(commits.map((c) => [c.hash, labelsOf(c, this.remotes, size ? size * advance : LABEL.CHAR)]));
    this.index = new Map(commits.map((c, i) => [c.hash, i]));
    this.ctx = { root: this.root, on: this.on, wcChange: this.wcChange, wcShort: this.wcShort, remotes: this.remoteNames, text: { font: look().font, size: look().size } };
    this.state = commits.length ? "ready" : "empty"; this.error = null;
    if (this.selected && !this.index.has(this.selected)) {
      // A snapshot rewrites @ under a new commit id: keep its details open.
      const wc = commits.find((c) => c.wc);
      if (wc && this.selectedWc) this.pick(wc, null, true);
      else { this.selected = null; this.details = null; this.diff = null; }
    }
  }

  // Working tree edits snapshot @; a new operation (from here or any terminal) reloads the log.
  watch(root, cx) {
    if (this.watching === root) return;
    this.watching = root;
    const token = this.watchToken, jjDir = `${root}/.jj`, gitDir = `${root}/.git`;
    const inside = (p, dir) => p === dir || p.startsWith(`${dir}/`);
    cx.spawn(async (cx) => {
      try {
        while (token === this.watchToken) {
          const paths = (await watchFolder(root)).map((p) => p.replace(/\\/g, "/"));
          if (token !== this.watchToken) return;
          // jj's own writes under .jj and .git must not start another snapshot, or it would loop.
          if (paths.some((p) => !inside(p, jjDir) && !inside(p, gitDir))) this.snapshotSoon(cx);
        }
      } catch { if (token === this.watchToken) this.pollTree = true; }
    });
    cx.spawn(async (cx) => {
      // A secondary workspace's .jj/repo is a file naming the shared repository.
      const pointer = (await readTextFile(`${jjDir}/repo`).catch(() => null))?.trim();
      const repo = pointer ? (pointer.startsWith("/") ? pointer : `${jjDir}/${pointer}`) : `${jjDir}/repo`;
      try {
        while (token === this.watchToken) {
          await watchFolder(`${repo}/op_heads/heads`);
          if (token !== this.watchToken) return;
          this.refresh(cx);
        }
      } catch { if (token === this.watchToken) this.pollOps = true; }
    });
  }

  snapshotSoon(cx) {
    if (this.snapshotTimer) return;
    this.snapshotTimer = true;
    cx.timer.after(Math.max(0, 1500 - (Date.now() - (this.lastSnapshot ?? 0))), (cx) => {
      this.snapshotTimer = false; this.lastSnapshot = Date.now(); this.snapshot(cx);
    });
  }

  snapshot(cx) {
    if (this.snapshotting || !this.root) return;
    this.snapshotting = true;
    const { root, on } = this;
    cx.spawn(async (cx) => {
      try { await exec("jj", ["util", "snapshot", "--no-pager", "--color=never"], { cwd: root, on }); } catch {}
      this.snapshotting = false;
      this.refresh(cx);
    });
  }

  checkOp(cx) {
    const { root, on } = this;
    cx.spawn(async (cx) => {
      const r = await exec("jj", ["op", "log", ...READ, "--no-graph", "-n", "1", "-T", "id"], { cwd: root, on }).catch(() => null);
      if (r?.code === 0 && r.stdout.trim() !== this.op) this.refresh(cx);
    });
  }

  loadMore(cx) { this.limit += PAGE; this.refresh(cx); cx.notify(); }
  setScope(all, cx) { if (this.all !== all) { this.all = all; this.limit = PAGE; this.refresh(cx); } cx.notify(); }
  setRemotes(cx) { this.remotes = !this.remotes; if (this.root) this.build(); cx.notify(); }

  run(action, flag, cx) {
    if (this[flag] || !this.ctx) return;
    this[flag] = true;
    const ctx = this.ctx;
    cx.spawn(async (cx) => {
      await perform(action, {}, ctx).catch(() => {});
      this[flag] = false; this.refresh(cx); cx.notify();
    });
    cx.notify();
  }

  graphWidth() { return this.cols.graph ? this.clampColumn("graph", this.cols.graph) : Math.min(Math.max(GRAPH_MIN, PAD * 2 + this.lanes * LANE), this.graphMax); }
  charWidth() { const { size, advance } = look(); return size ? size * advance : LABEL.CHAR; }
  changeWidth() { return Math.ceil(CHANGE_CHARS * this.charWidth()) + 2; }
  trailing() { return this.wide ? ["date", "author", "hash"] : this.narrow ? [] : ["date"]; }

  clampColumn(key, w) {
    const { min, max = (this.width ?? Infinity) * 0.7 } = COLUMNS[key];
    return Math.round(Math.max(min, Math.min(max, w)));
  }

  startDrag(key, e, cx) {
    cx.stop_propagation();
    if (e.click_count < 2) { this.drag = { key, x: e.position.x, from: key === "graph" ? this.graphWidth() : this.cols[key] }; return; }
    if (this.cols[key] !== COLUMNS[key].width) { this.cols = { ...this.cols, [key]: COLUMNS[key].width }; this.saveColumns(); cx.notify(); }
  }

  moveDrag(e, cx) {
    const d = this.drag;
    if (!d) return;
    if (d.axis === "y") {
      const h = this.clampDetail(d.from - (e.position.y - d.y) / this.unit());
      if (h !== this.detail) { this.detail = h; d.moved = true; cx.notify(); }
      return;
    }
    const w = this.clampColumn(d.key, d.from + COLUMNS[d.key].side * (e.position.x - d.x) / this.unit());
    if (w !== this.cols[d.key]) { this.cols = { ...this.cols, [d.key]: w }; d.moved = true; cx.notify(); }
  }

  endDrag(cx) {
    const d = this.drag;
    if (!d) return;
    this.drag = null;
    if (d.moved) { if (d.axis === "y") this.saveDetail(); else this.saveColumns(); }
    cx.notify();
  }

  saveColumns() { this.seenCols = JSON.stringify(this.cols); setShared("jj-graph.columns", this.cols); }

  clampDetail(h) {
    const room = Math.max(DETAIL_MIN, (this.height ?? 900) - CHROME_H - DETAIL_ROWS * this.rowH());
    return Math.round(Math.max(DETAIL_MIN, Math.min(room, h)));
  }
  detailHeight() {
    if (this.detail > 0) return this.clampDetail(this.detail);
    const rows = (this.commits.length + (this.hasMore ? 1 : 0)) * this.rowH();
    return this.clampDetail(Math.max(DETAIL_DEFAULT, (this.height ?? 900) - CHROME_H - rows));
  }
  startDetailDrag(e, cx) {
    cx.stop_propagation();
    if (e.click_count >= 2) { this.detail = 0; this.seenDetail = 0; setShared("jj-graph.details", 0); cx.notify(); return; }
    this.drag = { axis: "y", y: e.position.y, from: this.detailHeight() };
  }
  saveDetail() { this.seenDetail = this.detail; setShared("jj-graph.details", this.detail); }
  labelStart() { return this.graphWidth() + LABEL.GAP + this.changeWidth(); }
  labelLimit() {
    if (!this.width) return Infinity;
    return this.width - 2 - 10 - this.trailing().reduce((n, k) => n + this.cols[k] + LABEL.GAP, 0);
  }
  unit() { return this.scale ?? settings().zoom ?? 1; }
  rowPx() { return Math.max(1, Math.round(ROW * (settings().zoom ?? 1))); }
  rowH() { return this.rowPx() / (settings().zoom ?? 1); }
  listRow() { return listsZoom() ? this.rowH() : this.rowPx(); }
  pathScale() { return listsZoom() ? 1 : this.unit(); }

  // A left press, then on release the list names the row: together, a click.
  clicked(key, cx) {
    const press = this.press; this.press = null;
    if (key === "more") return this.loadMore(cx);
    const commit = this.commits[this.index.get(key)];
    if (!commit) return;
    if (press?.count >= 2) return this.activate(commit, press.x, cx);
    this.pick(commit, cx);
  }

  // A double-click edits a mutable change, or starts a new one on an immutable change or a label.
  activate(commit, x, cx) {
    const hit = hitLabel(this.labels.get(commit.hash), x, this.labelStart(), this.labelLimit());
    const short = hit ? hit.part.name : shortOf(commit), ctx = this.ctx;
    const action = !hit && !commit.immutable && !commit.root ? { type: "edit", rev: revOf(commit), short } : { type: "new", rev: revOf(commit), short };
    if (action.type === "edit" && commit.wc) return;
    cx.spawn(async () => { await perform(action, {}, ctx); });
  }

  contextMenu(key, e, cx) {
    const commit = this.commits[this.index.get(key)];
    if (!commit || !this.ctx) return;
    if (e.bounds?.height) this.scale = e.bounds.height / this.rowH();
    const x = (e.local_position?.x ?? 0) / this.unit();
    const hit = hitLabel(this.labels.get(key), x, this.labelStart(), this.labelLimit());
    const parent = commit.parents.length === 1 ? this.commits[this.index.get(commit.parents[0])] : null;
    const target = hit ? { kind: hit.part.kind, name: hit.part.name, ref: hit.part.ref, commit: brief(commit) }
      : { kind: "change", commit: brief(commit), squashable: Boolean(parent && !parent.immutable && !commit.indirect?.size),
        bothDescribed: Boolean(parent && commit.subject && parent.subject) };
    const items = menuFor(target, this.ctx);
    openOverlay({ mod: "jj-graph", kind: "popup", at: "pointer", width: 268, height: menuHeight(items), props: { role: "menu", target, ctx: this.ctx } });
  }

  pick(commit, cx, keepOpen = false) {
    if (!keepOpen && this.selected === commit.hash) { this.selected = null; this.details = null; this.diff = null; cx?.notify(); return; }
    const path = keepOpen ? this.diff?.path : null;
    this.selected = commit.hash; this.selectedWc = commit.wc; this.details = null; if (!keepOpen) this.diff = null;
    this.loadDetails(commit, path);
    if (!keepOpen) this.handle.focus();
    cx?.notify();
  }

  // Details are spawned from the copy's own context, so a rebuild without a cx can ask too.
  loadDetails(commit, diffPath = null) {
    const hash = commit.hash, root = this.root, on = this.on, key = `${on}\0${root}\0${hash}`;
    const known = this.commitDetails.get(key);
    if (known) { this.details = known; if (diffPath) this.openDiff(diffPath); return; }
    this.pendingDetails = { commit, key, diffPath };
  }

  fetchDetails(cx) {
    const pending = this.pendingDetails;
    if (!pending) return;
    this.pendingDetails = null;
    const { commit, key, diffPath } = pending, hash = commit.hash, root = this.root, on = this.on;
    const jj = (args) => exec("jj", args, { cwd: root, on });
    cx.spawn(async (cx) => {
      try {
        const [body, diff] = await Promise.all([jj(describeArgs(hash)), jj(diffArgs(hash))]);
        if (body.code !== 0) throw new Error(jjError(body));
        if (diff.code !== 0) throw new Error(jjError(diff));
        const files = parseGitDiff(diff.stdout);
        const details = { message: body.stdout.trim(), files: files.slice(0, 500), more: Math.max(0, files.length - 500) };
        if (diff.stdout.length < 1_000_000) keep(this.commitDetails, key, details, DETAILS);
        if (this.selected === hash) { this.details = details; if (diffPath) this.openDiff(diffPath); }
      } catch (e) { if (this.selected === hash) this.details = { error: String(e?.message ?? e) }; }
      cx.notify();
    });
  }

  openDiff(path) {
    const file = this.details?.files?.find((f) => f.path === path);
    if (!file) { this.diff = null; return; }
    const rows = diffRows(file.text) ?? [{ kind: "", text: file.binary ? "Binary file changed" : "No text changes" }];
    this.diff = { path, rows, width: Math.max(300, ...rows.map((r) => r.text.length * this.charWidth() + 60)) };
  }

  // ---- drawing

  ts(n) { return look().size ?? n; }

  graphCell(row, commit, colors, t, width) {
    const x = (lane) => PAD + lane * LANE + LANE / 2, y = (v) => v * this.rowH(), paths = new Map();
    const z = this.pathScale(), px = (lane) => x(lane) * z, py = (v) => y(v) * z;
    // One stroked path per color: a row is a handful of paints, however many lanes cross it.
    for (const [a, ya, b, yb, c, dashed] of row.segments) {
      const color = colors[c % colors.length], key = `${color}${dashed ? "-" : ""}`;
      let p = paths.get(key)?.p ?? (dashed ? PathBuilder.stroke(1.5 * z).dash_array([3 * z, 3 * z]) : PathBuilder.stroke(1.5 * z));
      p = p.move_to(px(a), py(ya));
      if (a === b) p = p.line_to(px(b), py(yb));
      else { const mid = (py(ya) + py(yb)) / 2; p = p.cubic_bezier_to(px(b), py(yb), px(a), mid, px(b), mid); }
      paths.set(key, { p, color });
    }
    const color = commit.conflict ? t.ansi1 : colors[row.lane % colors.length];
    const dot = div().absolute().left(x(row.lane) - 4).top(this.rowH() / 2 - 4).size(8);
    // @ is a ring, immutable changes are squares, as jj marks them with @ and ◆.
    const node = commit.wc ? dot.rounded(4).bg(t.background).border(2).border_color(t.accent)
      : commit.immutable ? dot.rounded(1).bg(color) : dot.rounded(4).bg(color);
    return div().relative().flex_none().w(width).h(this.rowH()).overflow_hidden()
      .children([...paths.values()].map(({ p, color }) => window.paint_path(p.build(), color).absolute().top(0).left(0).size_full()))
      .child(node);
  }

  label(label, color, t) {
    const edge = label.kind === "tag" ? t.ansi3 : label.kind === "remote" ? t.muted : color;
    return h_flex().flex_none().w(label.width).h(20).rounded(5).border_1().border_color(edge).overflow_hidden()
      .children(label.parts.map((part, i) => {
        const fg = part.kind === "tag" ? t.ansi3 : i > 0 || part.kind === "remote" ? t.muted : t.foreground;
        const glyph = part.kind === "bookmark" ? "branch" : part.kind === "tag" ? "tag" : "cloud";
        return h_flex().w(part.width).h_full().flex_none().px(LABEL.PAD).gap(3).items_center().overflow_hidden()
          .when(i > 0, (e) => e.border_l(1).border_color(edge).bg(edge + "1f"))
          .when(Boolean(part.icon), (e) => e.child(svg(icon(glyph)).size(10).flex_none().text_color(fg)))
          .child(div().text_size(this.ts(LABEL.FONT)).whitespace_nowrap().text_color(fg).child(part.text));
      }));
  }

  row(i, t, colors, width) {
    const commit = this.commits[i], row = this.rows[i], color = colors[row.lane % colors.length];
    const fg = commit.immutable ? t.muted : t.foreground;
    const tag = (text, c) => div().flex_none().text_color(c).child(text);
    const names = commit.refs.filter((r) => r.kind !== "remote" || this.remotes).map((r) => r.name);
    const hover = [commit.root ? "root()" : commit.subject || "(no description set)", ...(names.length ? [names.join(", ")] : [])].join("  |  ");
    return h_flex().id(`c-${commit.hash}`).tooltip(hover).w_full().h(this.rowH()).flex_none().pr(10).gap(LABEL.GAP).items_center().overflow_hidden()
      .when(commit.wc, (e) => e.bg(t.accent + "14")).when(this.selected === commit.hash, (e) => e.bg(t.selected)).hover((s) => s.bg(t.hover))
      .child(this.graphCell(row, commit, colors, t, width))
      .child(h_flex().flex_1().min_w(0).h_full().gap(LABEL.GAP).items_center().overflow_hidden()
        .child(h_flex().w(this.changeWidth()).flex_none().overflow_hidden()
          .child(div().text_color(t.ansi5).font_semibold().child(commit.prefix))
          .child(div().text_color(t.dim).child(commit.rest)))
        .children(this.labels.get(commit.hash).map((l) => this.label(l, color, t)))
        .when(commit.divergent, (e) => e.child(tag("divergent", t.ansi1)))
        .when(commit.conflict, (e) => e.child(tag("conflict", t.ansi1)))
        .when(commit.empty && !commit.root, (e) => e.child(tag("(empty)", t.ansi2)))
        .child(div().flex_1().min_w(0).truncate().text_color(commit.subject ? fg : t.dim).when(commit.wc, (e) => e.font_semibold())
          .child(commit.root ? "root()" : commit.subject || "(no description set)")))
      .when(!this.narrow, (e) => e.child(div().w(this.cols.date).flex_none().text_right().truncate().text_color(t.dim).child(commit.root ? "" : ago(commit.time))))
      .when(this.wide, (e) => e
        .child(div().w(this.cols.author).flex_none().truncate().text_color(t.muted).child(commit.author))
        .child(div().w(this.cols.hash).flex_none().truncate().text_color(t.dim).child(commit.hash.slice(0, 8))));
  }

  iconButton(id, glyph, label, tip, action, t) {
    return h_flex().id(id).tooltip(label).accessibility_label(label).h(24).px(6).gap(5).flex_none().items_center().rounded(6).cursor_pointer()
      .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action)
      .child(svg(icon(glyph)).size(13).flex_none()).when(Boolean(tip), (e) => e.child(tip));
  }

  header(t) {
    const ready = this.state === "ready" || this.state === "empty", overlay = props()?.overlay;
    return h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
      .child(div().font_semibold().child("jj"))
      .when(Boolean(this.root) && !this.narrow, (e) => e.child(div().min_w(0).truncate().text_color(t.dim).child(tilde(this.root, this.on))))
      .when(ready && Boolean(this.wcShort), (e) => e.child(h_flex().h(22).px(7).gap(5).flex_none().items_center().rounded(6).bg(t.accent + "26").text_color(t.accent)
        .child(div().font_semibold().child(`@ ${this.wcShort}`))))
      .child(div().flex_1())
      .when(ready, (e) => e.child(this.iconButton("jj-undo", "revert", "Undo the last jj operation", this.narrow ? null : this.undoing ? "Undoing…" : "Undo", (_e, cx) => this.run({ type: "undo" }, "undoing", cx), t)))
      .when(ready && this.remoteNames?.length > 0, (e) => e.child(this.iconButton("jj-fetch", "fetch", "Fetch from every remote", this.fetching ? "Fetching…" : null, (_e, cx) => this.run({ type: "fetch" }, "fetching", cx), t)))
      .when(this.state !== "nofolder", (e) => e.child(this.iconButton("jj-refresh", "refresh", "Read the log again", null, (_e, cx) => this.snapshot(cx), t)))
      .when(Boolean(overlay), (e) => e.child(h_flex().id("jj-close").tooltip("Close").h(24).px(7).flex_none().items_center().rounded(6).cursor_pointer()
        .text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(() => closeOverlay(overlay)).child("×")));
  }

  toolbar(t) {
    const segment = (id, text, on, action) => div().id(id).h(22).px(9).flex().items_center().rounded(5).cursor_pointer()
      .bg(on ? t.raised : t.background).text_color(on ? t.foreground : t.muted).when(on, (e) => e.border_1().border_color(t.border))
      .hover((s) => s.text_color(t.foreground)).on_click(action).child(text);
    return h_flex().h(34).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.border)
      .child(h_flex().p(2).gap(2).rounded(7).bg(t.background).border_1().border_color(t.border)
        .child(segment("jj-log", "Log", !this.all, (_e, cx) => this.setScope(false, cx)))
        .child(segment("jj-all", "All", this.all, (_e, cx) => this.setScope(true, cx))))
      .child(h_flex().id("jj-remotes").h(24).px(6).gap(6).items_center().rounded(6).cursor_pointer().text_color(t.muted)
        .hover((s) => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => this.setRemotes(cx))
        .child(div().size(13).rounded(3).border_1().border_color(this.remotes ? t.accent : t.input).when(this.remotes, (e) => e.bg(t.accent)).flex().items_center().justify_center()
          .when(this.remotes, (e) => e.child(svg(icon("check")).size(10).text_color(t.accent_foreground))))
        .child("Remotes"));
  }

  columns(t, width) {
    const head = (text, w) => div().when(w !== undefined, (e) => e.w(w).flex_none()).truncate().child(text);
    const titles = { date: "Date", author: "Author", hash: "Commit" };
    const handle = (key) => div().id(`jj-col-${key}`).w(LABEL.GAP + 2).mx(-1).h_full().flex_none().flex().justify_center().cursor_col_resize()
      .on_mouse_down("left", (e, cx) => this.startDrag(key, e, cx))
      .child(div().w(1).h_full().when(this.drag?.key === key, (e) => e.bg(t.accent)))
      .hover((s) => s.bg(t.border));
    return h_flex().h(24).flex_none().pr(10).items_center().border_b(1).border_color(t.border).text_color(t.dim)
      .child(head("Graph", width).pl(PAD)).child(handle("graph")).child(div().flex_1().min_w(0).child("Change"))
      .children(this.trailing().flatMap((k) => [handle(k), head(titles[k], this.cols[k]).when(k === "date", (e) => e.text_right())]));
  }

  list(t) {
    const colors = laneColors(t), width = this.graphWidth(), n = this.commits.length + (this.hasMore ? 1 : 0);
    return div().flex_1().min_h(0).relative()
      .on_mouse_down("left", (e) => { this.press = { x: (e.local_position?.x ?? 0) / this.unit(), count: e.click_count }; })
      .child(v_virtual_list(this.listId, n, this.listRow(), (i) => this.commits[i]?.hash ?? "more",
        (range, cx) => {
          if (range.end > this.commits.length && this.hasMore && !this.loading && this.moreAsked !== this.limit) {
            this.moreAsked = this.limit;
            cx.spawn(async (cx) => this.loadMore(cx));
          }
          return Array.from({ length: range.end - range.start }, (_x, k) => range.start + k).map((i) => i < this.commits.length
            ? this.row(i, t, colors, width)
            : div().id("jj-more").h(this.rowH()).flex_none().px(14).flex().items_center().text_color(t.accent).hover((s) => s.bg(t.hover))
              .child(this.loading ? "Loading more…" : `Load ${PAGE} more`));
        })
        .on_item_click((key, cx) => this.clicked(key, cx))
        .on_item_secondary_click((key, e, cx) => this.contextMenu(key, e, cx))
        .size_full())
      .child(Scrollbar.vertical(this.listId).viewport_from_layout().absolute().inset_0());
  }

  detailsPane(t) {
    const commit = this.commits[this.index.get(this.selected)], d = this.details;
    if (!commit) return div();
    const grip = div().id("jj-details-grip").h(6).w_full().flex_none().border_t(1).border_color(t.border).cursor_row_resize()
      .on_mouse_down("left", (e, cx) => this.startDetailDrag(e, cx))
      .hover((s) => s.bg(t.accent));
    const top = h_flex().h(32).flex_none().px(10).gap(6).items_center().border_b(1).border_color(t.border);
    const close = div().id("jj-details-close").px(6).py(1).rounded(4).text_color(t.dim).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { this.selected = null; this.details = null; this.diff = null; cx.notify(); }).child("×");
    if (this.diff) {
      const rows = this.diff.rows;
      return v_flex().flex_none().h(this.detailHeight())
        .child(grip)
        .child(top.child(div().id("jj-diff-back").px(6).py(1).rounded(4).text_color(t.muted).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground))
            .on_click((_e, cx) => { this.diff = null; cx.notify(); }).child("← Files"))
          .child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(this.diff.path)).child(close))
        .child(div().flex_1().min_h(0).relative()
          .child(div().id(`${this.diffId}-x`).size_full().overflow_x_scrollbar()
            .child(div().w_full().min_w(this.diff.width).h_full().child(v_virtual_list(this.diffId, rows.length, DIFF_ROW, (i) => String(i),
              (range) => rows.slice(range.start, range.end).map((r) => this.diffRow(r, t))).size_full())))
          .child(Scrollbar.vertical(this.diffId).viewport_from_layout().absolute().inset_0()));
    }
    const body = v_flex().id("jj-details").flex_1().min_h(0).overflow_y_scrollbar().px(14).py(10).gap(4);
    const pane = (content) => v_flex().flex_none().h(this.detailHeight())
      .child(grip)
      .child(top.child(div().flex_1().text_color(t.muted).child(`Change ${shortOf(commit)}`)).child(close))
      .child(content);
    if (d?.error) return pane(body.child(div().text_color(t.ansi1).child(d.error)));
    const meta = (k, v, color) => h_flex().gap(8).child(div().w(72).flex_none().text_color(t.dim).child(k)).child(div().min_w(0).truncate().text_color(color ?? t.muted).child(v));
    const parentName = (p) => { const c = this.commits[this.index.get(p)]; return c ? shortOf(c) : p.slice(0, 8); };
    const head = body
      .child(div().font_semibold().child(commit.subject || "(no description set)"))
      .child(meta("Change", commit.change, t.ansi5))
      .child(meta("Commit", commit.hash, t.accent))
      .child(meta("Parents", commit.parents.map(parentName).join(", ") || "none"))
      .when(!commit.root, (e) => e.child(meta("Author", `${commit.author} <${commit.email}>`)).child(meta("Date", `${stamp(commit.time)} · ${ago(commit.time)}`)));
    if (!d) return pane(head.child(div().pt(8).text_color(t.dim).child("Loading files…")));
    const add = d.files.reduce((n, f) => n + f.add, 0), del = d.files.reduce((n, f) => n + f.del, 0);
    const lines = d.message.split("\n").slice(1).join("\n").trim();
    return pane(head
      .when(Boolean(lines), (el) => el.child(v_flex().pt(6).children(lines.split("\n").map((line) => div().text_color(t.muted).child(line || " ")))))
      .child(h_flex().pt(8).pb(2).gap(8).items_center()
        .child(div().text_color(t.muted).child(count(d.files.length + d.more, "file")))
        .when(add > 0 || del > 0, (e) => e.child(div().text_color(t.ansi2).child(`+${add}`)).child(div().text_color(t.ansi1).child(`−${del}`))))
      .children(d.files.map((f, i) => {
        const parts = f.path.split("/"), name = parts.pop();
        const sc = f.status === "A" ? t.ansi2 : f.status === "D" ? t.ansi1 : t.blocked;
        return h_flex().id(`jf-${i}`).h(24).flex_none().px(6).gap(8).items_center().rounded(6).cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => { this.openDiff(f.path); cx.notify(); })
          .child(div().w(12).flex_none().text_color(sc).child(f.status))
          .child(h_flex().flex_1().min_w(0).child(div().text_color(t.dim).truncate().child(parts.length ? parts.join("/") + "/" : "")).child(div().min_w(0).truncate().child(name)))
          .when(f.add > 0, (e) => e.child(div().text_color(t.ansi2).child(`+${f.add}`)))
          .when(f.del > 0, (e) => e.child(div().text_color(t.ansi1).child(`−${f.del}`)));
      }))
      .when(d.more > 0, (e) => e.child(div().text_color(t.dim).child(`and ${d.more} more`))));
  }

  diffRow({ kind, number, text }, t) {
    if (kind === "@") return div().w_full().px(12).h(DIFF_ROW).flex_none().truncate().bg(t.raised).text_color(t.dim).child(text);
    return h_flex().w_full().h(DIFF_ROW).flex_none().gap(10).when(kind === "+", (e) => e.bg(t.ansi2 + "18")).when(kind === "-", (e) => e.bg(t.ansi1 + "18"))
      .child(div().w(40).flex_none().text_right().text_color(t.dim).child(number === undefined ? "" : String(number)))
      .child(div().flex_1().min_w(0).whitespace_nowrap().child(text));
  }

  empty(t) {
    const s = this.state, where = tilde(this.cwd, this.on);
    const [glyph, title, body] = s === "nofolder" ? ["folder", "No folder", "Focus a terminal to see the log of the repository it's in."]
      : s === "norepo" ? ["folder", "Not a jj repository", `${where ?? "This folder"} isn't inside a jj repository.`]
      : s === "empty" ? ["commit", "Nothing to show", "The log revset matches no changes."]
      : s === "error" ? ["graph", "Can't read the log", this.error]
      : ["graph", "Loading log…", ""];
    return v_flex().flex_1().min_h(0).items_center().justify_center().gap(10).px(28).pb(40)
      .child(div().size(46).rounded(12).bg(t.raised).border_1().border_color(t.border).flex().items_center().justify_center()
        .child(svg(icon(glyph)).size(22).text_color(s === "error" ? t.ansi1 : t.muted)))
      .child(div().font_semibold().text_color(t.foreground).child(title))
      .when(Boolean(body), (e) => e.child(div().max_w(320).text_center().text_color(t.muted).child(body)));
  }

  render(cx) {
    if (this.key() !== this.context) this.refresh(cx);
    this.fetchDetails(cx);
    const changed = shared("jj-graph.changed");
    const savedCols = shared("jj-graph.columns"), seen = JSON.stringify(savedCols ?? null);
    if (!this.drag && seen !== this.seenCols) { this.seenCols = seen; this.cols = withDefaults(savedCols); }
    const savedDetail = Number(shared("jj-graph.details")) || 0;
    if (!this.drag && savedDetail !== this.seenDetail) { this.seenDetail = savedDetail; this.detail = savedDetail; }
    if (changed !== this.seenChange) { this.seenChange = changed; if (this.root) this.refresh(cx); }
    const t = theme(), { font, size } = look(), ready = this.state === "ready", overlay = props()?.overlay;
    // In a window, presses on the body stay with the mod; the header is left to drag it by.
    const body = v_flex().flex_1().min_h(0).when(Boolean(overlay), (e) => e.on_mouse_down("left", (_e, cx) => cx.stop_propagation()))
      .when(ready, (e) => e.child(this.toolbar(t)).child(this.columns(t, this.graphWidth())).child(this.list(t))
        .when(Boolean(this.selected), (el) => el.child(this.detailsPane(t))))
      .when(!ready, (e) => e.child(this.empty(t)));
    return v_flex().id("jj-graph").size_full().min_h(0).overflow_hidden().bg(t.background).border_1().border_color(t.border)
      .text_color(t.foreground).text_size(size ?? 12.5).when(Boolean(font), (e) => e.font_family(font)).track_focus(this.handle)
      .on_mouse_move((e, cx) => this.moveDrag(e, cx))
      .on_mouse_up("left", (_e, cx) => this.endDrag(cx))
      .on_hover((hovered, cx) => { if (!hovered) this.endDrag(cx); })
      .on_key_down((e, cx) => {
        if (e.key !== "escape") return;
        if (this.diff) this.diff = null;
        else if (this.selected) { this.selected = null; this.details = null; }
        else if (overlay) closeOverlay(overlay);
        else return;
        cx.stop_propagation(); cx.notify();
      })
      .on_size_change((sz, cx) => {
        const width = sz.width / this.unit(), wide = width >= 600, narrow = width < 360, graphMax = Math.max(60, Math.round(width * (narrow ? 0.3 : 0.4)));
        this.width = width;
        const height = sz.height / this.unit(), resized = height !== this.height && Boolean(this.selected);
        this.height = height;
        if (wide !== this.wide || narrow !== this.narrow || graphMax !== this.graphMax || resized) { this.wide = wide; this.narrow = narrow; this.graphMax = graphMax; cx.notify(); }
      })
      .child(this.header(t))
      .child(body);
  }
}
