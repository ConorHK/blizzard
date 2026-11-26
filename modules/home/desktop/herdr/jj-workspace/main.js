// The jj counterpart of Herdr's worktree dialog: { space, action: "new" | "open" | "remove" },
// or { folder, machine } for a repo without a space; optional { font, size }.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, Scrollbar } from "gpui-base";
import { run, props, closeOverlay, theme, spaces, panes, exec, home } from "herdr";

const READ = ["--ignore-working-copy", "--no-pager", "--color=never"];
const LIST = 'name ++ "\\t" ++ root ++ "\\t" ++ target.change_id().shortest() ++ "\\t" ++ target.description().first_line() ++ "\\n"';
// A secondary workspace's .jj/repo is a file naming the main one's store, relative to .jj.
const MAIN_ROOT = 'cd .jj && if [ -f repo ]; then cd "$(cat repo)"; else cd repo; fi && cd ../.. && pwd';

// Workspaces go to <ROOT>/<repo>/<name>, as Herdr's worktrees do.
const ROOT = (userHome) => `${userHome}/.herdr/workspaces`;
const tilde = (path, userHome) => (userHome && path.startsWith(userHome) ? `~${path.slice(userHome.length)}` : path);
const slug = (name) => name.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
const inside = (p, dir) => p === dir || p.startsWith(`${dir}/`);

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s) {
  if (!s) return null;
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder || null;
}

async function sh(cwd, cmd, args, on) {
  const r = await exec(cmd, args, cwd ? { cwd, on } : { on });
  return { ok: r.code === 0, out: (r.stdout ?? "").trim(), err: (r.stderr ?? r.stdout ?? "").trim() };
}

// The repo a folder is in: this workspace's root, the main one's, and its name. null outside jj.
async function repoOf(folder, on) {
  const top = await sh(folder, "jj", ["workspace", "root", ...READ], on);
  if (!top.ok) return null;
  const main = await sh(top.out, "sh", ["-c", MAIN_ROOT], on);
  if (!main.ok) throw new Error(main.err || "Could not find the main workspace.");
  return { top: top.out, main: main.out, name: main.out.split("/").pop(), linked: main.out !== top.out };
}

// Every workspace with a known root, the default first: { name, path, change, title }.
async function workspaces(repo, on) {
  const r = await sh(repo.top, "jj", ["workspace", "list", ...READ, "-T", LIST], on);
  if (!r.ok) throw new Error(r.err || "jj workspace list failed.");
  return r.out.split("\n").filter(Boolean).map((l) => l.split("\t"))
    .map(([name, path, change, title]) => ({ name, path: path || (name === "default" ? repo.main : ""), change, title }))
    .filter((w) => w.path)
    .sort((a, b) => (b.name === "default") - (a.name === "default"));
}

// The space showing a workspace: its first terminal is in it, and in no deeper workspace.
function spaceOf(path, all, on) {
  return spaces().find((s) => {
    if ((s.machine ?? null) !== (on ?? null)) return false;
    const at = place(s);
    return Boolean(at) && inside(at, path) && !all.some((w) => w.path.length > path.length && inside(at, w.path));
  });
}

export default class JjWorkspace extends View {
  init(_props, cx) {
    const p = props() ?? {};
    this.action = p.action ?? "new";
    this.on = this.space()?.machine ?? null;
    this.userHome = this.on ? null : home();
    this.text = "";
    this.list = undefined;
    this.at = 0;
    this.busy = false;
    this.error = "";
    this.repo = undefined;
    this.input = InputState.new({ value: "", placeholder: this.action === "open" ? "filter workspaces" : "workspace name" });
    this.input.on("change", (_e, cx) => { this.text = this.input.value(); this.error = ""; this.at = 0; cx.notify(); });
    this.input.on("submit", (_e, cx) => this.go(cx));
    this.handle = cx.focus_handle();
    if (this.action === "remove") this.handle.focus();
    else {
      this.input.focus();
      cx.timer.after(600, () => this.input.focus());
    }
    cx.spawn(async (cx) => {
      try {
        if (this.on) {
          const r = await sh(null, "sh", ["-c", 'printf %s "$HOME"'], this.on);
          if (!r.ok || !r.out) throw new Error("Could not find the remote home folder.");
          this.userHome = r.out;
        }
        this.folder = p.folder || place(this.space()) || this.userHome;
        const repo = await repoOf(this.folder, this.on);
        if (repo && this.action === "open") this.list = await workspaces(repo, this.on);
        if (repo) this.ws = (await sh(repo.top, "jj", ["workspace", "list", ...READ, "-T", 'if(current_workspace, name)'], this.on)).out;
        this.repo = repo;
      } catch (error) {
        this.repo = null;
        this.error = String(error);
      }
      cx.notify();
    });
  }

  space() {
    const p = props() ?? {};
    return spaces().find((s) => s.id === p.space) ?? (p.folder ? { folder: p.folder, machine: p.machine ?? null } : undefined);
  }

  close() {
    closeOverlay(props().overlay);
  }

  go(cx) {
    if (this.busy || !this.repo) return;
    if (this.action === "open") return this.open(this.shown()[this.at]);
    this.busy = true;
    this.error = "";
    cx.notify();
    cx.spawn(async (cx) => {
      try { this.error = this.action === "remove" ? await this.remove() : await this.create(); }
      catch (error) { this.error = String(error); }
      this.busy = false;
      if (!this.error) this.close();
      cx.notify();
    });
  }

  async create() {
    const name = slug(this.text.trim());
    if (!name) return "Type a workspace name.";
    const parent = `${ROOT(this.userHome)}/${this.repo.name}`;
    const path = `${parent}/${name}`;
    const dir = await sh(null, "mkdir", ["-p", parent], this.on);
    if (!dir.ok) return dir.err || "mkdir failed.";
    const r = await sh(this.repo.top, "jj", ["workspace", "add", "--name", name, path], this.on);
    if (!r.ok) return r.err || "jj workspace add failed.";
    run("space.new", { name: `${this.repo.name}/${name}`, folder: path, machine: this.on });
    return "";
  }

  shown() {
    const f = this.text.trim().toLowerCase();
    return (this.list ?? []).filter((w) => !f || `${w.name} ${w.title} ${w.path}`.toLowerCase().includes(f));
  }

  open(w) {
    if (!w) return;
    this.close();
    const s = spaceOf(w.path, this.list, this.on);
    if (s) run("space.select", { id: s.id });
    else run("space.new", { name: `${this.repo.name}/${w.name}`, folder: w.path, machine: this.on });
  }

  // jj snapshots the workspace into a commit before it deletes the folder.
  async remove() {
    const s = this.space();
    if (s?.id) run("space.close", { id: s.id, confirmed: true });
    const r = await sh(this.repo.main, "jj", ["workspace", "remove", this.ws], this.on);
    return r.ok ? "" : r.err || "jj workspace remove failed.";
  }

  key(e, cx) {
    if (e.key === "escape") return this.close();
    if (this.action === "remove" && e.key === "enter") return this.go(cx);
    if (this.action !== "open") return;
    const n = this.shown().length;
    if (e.key === "enter") this.go(cx);
    else if ((e.key === "down" || e.key === "up") && n) this.at = (this.at + (e.key === "down" ? 1 : n - 1)) % n;
    else return;
    cx.stop_propagation();
    cx.notify();
  }

  field(t) {
    return Input.new(this.input).h(32).px(10).items_center().rounded(6).border(1).border_color(t.accent).bg(t.background).text_color(t.foreground);
  }

  row(w, i, t, ts) {
    const there = spaceOf(w.path, this.list, this.on);
    return v_flex().id(`ws-${i}`).flex_none().h(44).px(10).justify_center().rounded(7).cursor_pointer()
      .when(i === this.at, (el) => el.bg(t.selected))
      .when(i !== this.at, (el) => el.hover((s) => s.bg(t.hover)))
      .on_click(() => this.open(w))
      .child(h_flex().gap(8).items_center()
        .child(div().flex_none().text_color(t.foreground).child(w.name))
        .child(div().flex_1().min_w(0).truncate().text_color(t.dim).child(`${w.change} ${w.title}`))
        .when(Boolean(there), (el) => el.child(div().flex_none().text_size(ts(11)).text_color(t.accent).child("open"))))
      .child(div().truncate().text_size(ts(11.5)).text_color(t.dim).child(tilde(w.path, this.userHome)));
  }

  body(t, ts) {
    const r = this.repo;
    const where = this.folder ? tilde(this.folder, this.userHome) : "This folder";
    if (r === undefined) return [div().text_color(t.muted).child("…")];
    if (r === null) return [div().text_color(t.muted).child(this.error ? "" : `${where} is not in a jj repository.`)];
    if (this.action === "remove") {
      if (!r.linked) return [div().text_color(t.muted).child("This is the repository's main workspace.")];
      return [div().text_color(t.muted).child(`Closes the space and deletes ${tilde(r.top, this.userHome)}. Its changes stay in the jj log.`)];
    }
    if (this.action === "new")
      return [div().text_color(t.muted).child(`A new space on a workspace in ${tilde(ROOT(this.userHome), this.userHome)}/${r.name}/, on the same parent as this one.`), this.field(t)];
    const rows = this.shown();
    return [
      this.field(t),
      div().relative().flex_1().min_h(0)
        .child(v_flex().id("ws-list").size_full().overflow_y_scroll()
          .children(rows.map((w, i) => this.row(w, i, t, ts)))
          .when(rows.length === 0, (el) => el.child(div().p(10).text_color(t.dim).child("No matching workspaces."))))
        .child(Scrollbar.vertical("ws-list").absolute().inset_0()),
    ];
  }

  hint() {
    if (this.busy) return "working…";
    if (!this.repo || (this.action === "remove" && !this.repo.linked)) return "esc close";
    return { new: "↵ create · esc cancel", open: "↑↓ choose · ↵ open · esc close", remove: "↵ remove · esc cancel" }[this.action];
  }

  render() {
    const t = theme();
    const { font, size } = props() ?? {};
    const ts = (n) => size ?? n;
    const of = this.repo ? ` of ${this.repo.name}` : "";
    const title = { new: `New workspace${of}`, open: `Open workspace${of}`, remove: `Remove workspace ${this.ws ?? ""}?` }[this.action];
    return v_flex().id("jj-workspace").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().p(16).gap(10).bg(t.popover).text_size(ts(13))
      .when(Boolean(font), (el) => el.font_family(font))
      .child(div().font_semibold().text_color(t.foreground).child(title))
      .children(this.body(t, ts))
      .when(Boolean(this.error), (el) => el.child(div().text_color(t.blocked).child(this.error)))
      .when(this.action !== "open", (el) => el.child(div().flex_1()))
      .child(h_flex().justify_end().text_size(ts(11)).text_color(t.dim).child(this.hint()));
  }
}
