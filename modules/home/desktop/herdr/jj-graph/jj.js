// jj for the graph, with no herdr imports so node can test it: reading the log,
// the labels on each row, and the actions behind the menus. Commands are argv
// arrays, never a shell line.

// Reads never snapshot the working copy, so the panel's own reads write nothing under .jj.
export const READ = ["--no-pager", "--color=never", "--ignore-working-copy"];
// A write that would open an editor fails instead of hanging the panel.
export const WRITE = ["--no-pager", "--color=never", "--config=ui.editor=\"false\""];
export const ALL = "all()";

const FIELDS = 14;
export const TEMPLATE = String.raw`commit_id ++ "\0" ++ change_id ++ "\0"
  ++ change_id.shortest(8).prefix() ++ "\0" ++ change_id.shortest(8).rest() ++ "\0"
  ++ parents.map(|c| c.commit_id()).join(" ") ++ "\0"
  ++ author.name() ++ "\0" ++ author.email() ++ "\0" ++ committer.timestamp().format("%s") ++ "\0"
  ++ local_bookmarks.map(|b| b.name()).join("\x1f") ++ "\0"
  ++ remote_bookmarks.filter(|b| b.remote() != "git").map(|b| b.name() ++ "@" ++ b.remote() ++ if(b.tracked(), "\x1d")).join("\x1f") ++ "\0"
  ++ tags.map(|t| t.name()).join("\x1f") ++ "\0"
  ++ working_copies.map(|w| w.name() ++ "\x1e" ++ w.root() ++ "\x1e" ++ if(w.current_workspace(), "*")).join("\x1f") ++ "\0"
  ++ if(current_working_copy, "@") ++ if(empty, "e") ++ if(conflict, "c") ++ if(immutable, "i") ++ if(divergent, "d") ++ if(root, "r") ++ "\0"
  ++ description.first_line() ++ "\0"`;

export const commitId = (s) => typeof s === "string" && /^[0-9a-f]{40,64}$/.test(s);
export const changeId = (s) => typeof s === "string" && /^[k-z]{32}$/.test(s);
const revision = (s) => commitId(s) || changeId(s);
const refName = (s) => typeof s === "string" && s.length > 0 && !/^[-/]/.test(s)
  && !/[\x00-\x20\x7f~^:?*\[\\"'@]/.test(s) && !s.includes("..")
  && !s.endsWith(".") && s.split("/").every((p) => p && !p.startsWith(".") && !p.endsWith(".lock"));

export function logArgs({ revset, limit }) {
  return ["log", ...READ, "--no-graph", ...(revset ? ["-r", revset] : []), "-n", String(limit), "-T", TEMPLATE];
}

// The nearest shown ancestors of a commit outside the shown set, as jj's own graph finds them.
export function ancestorArgs(hash, revset) {
  if (!commitId(hash)) throw new Error("Invalid commit identity");
  return ["log", ...READ, "--no-graph", "-r", `heads(::${hash} & (${revset}))`, "-T", String.raw`commit_id ++ "\n"`];
}

const list = (s) => (s ? s.split("\x1f") : []);

export function parseLog(text) {
  if (!text) return [];
  const fields = text.split("\0");
  if (fields.pop() !== "" || fields.length % FIELDS !== 0) throw new Error("Invalid log framing");
  const commits = [];
  for (let i = 0; i < fields.length; i += FIELDS) {
    const [hash, change, prefix, rest, parents, author, email, time, locals, remotes, tags, workspaces, flags, subject] = fields.slice(i, i + FIELDS);
    const refs = [
      ...list(locals).map((name) => ({ kind: "bookmark", name })),
      ...list(remotes).map((raw) => {
        const tracked = raw.endsWith("\x1d"), name = tracked ? raw.slice(0, -1) : raw, at = name.lastIndexOf("@");
        return { kind: "remote", name, bookmark: name.slice(0, at), remote: name.slice(at + 1), tracked };
      }),
      ...list(tags).map((name) => ({ kind: "tag", name })),
      ...list(workspaces).map((raw) => {
        const [name, path, current] = raw.split("\x1e");
        return { kind: "workspace", name, path, current: current === "*" };
      }),
    ];
    const commit = {
      hash, change, prefix, rest, parents: parents ? parents.split(" ") : [], author, email, time: Number(time), refs, subject,
      wc: flags.includes("@"), empty: flags.includes("e"), conflict: flags.includes("c"), immutable: flags.includes("i"),
      divergent: flags.includes("d"), root: flags.includes("r"),
    };
    if (!commitId(hash) || !changeId(change) || !commit.parents.every(commitId)) throw new Error("Invalid commit identity");
    if (!/^-?\d+$/.test(time)) throw new Error("Invalid commit time");
    commits.push(commit);
  }
  return commits;
}

// A divergent change id names several commits, so those are acted on by commit id.
export const revOf = (c) => (c.divergent ? c.hash : c.change);

// Labels are drawn at these exact widths (monospace text, fixed padding and
// icon), so a press can be matched to the label under it: a virtual list's
// rows can't hold their own handlers.
export const LABEL = { CHAR: 6.6, PAD: 5, ICON: 13, GAP: 6, MAX: 22, FONT: 11 };
const fit = (s, n) => (s.length > n ? s.slice(0, n - 1) + "…" : s);
const partWidth = (part, char) => Math.ceil(LABEL.PAD * 2 + (part.icon ? LABEL.ICON : 0) + part.text.length * char) + 1;

// Workspace labels show only once the repo has a second workspace, as jj log's own <name>@ markers do.
export function labelsOf(commit, remotesShown = true, char = LABEL.CHAR, workspacesShown = false) {
  const labels = [], remotes = remotesShown ? commit.refs.filter((r) => r.kind === "remote") : [], paired = new Set();
  if (workspacesShown) for (const ref of commit.refs) if (ref.kind === "workspace") labels.push({ kind: "workspace", parts: [{ kind: "workspace", name: ref.name, ref, text: fit(`${ref.name}@`, LABEL.MAX), icon: true }] });
  for (const ref of commit.refs) {
    if (ref.kind !== "bookmark") continue;
    // A remote bookmark at the same commit rides on its local bookmark's label.
    const parts = [{ kind: "bookmark", name: ref.name, text: fit(ref.name, LABEL.MAX), icon: true }];
    for (const remote of remotes) {
      if (remote.bookmark !== ref.name || paired.has(remote.name)) continue;
      paired.add(remote.name);
      parts.push({ kind: "remote", name: remote.name, ref: remote, text: fit(remote.remote, 12) });
    }
    labels.push({ kind: "bookmark", parts });
  }
  for (const remote of remotes) if (!paired.has(remote.name)) labels.push({ kind: "remote", parts: [{ kind: "remote", name: remote.name, ref: remote, text: fit(remote.name, LABEL.MAX), icon: true }] });
  for (const ref of commit.refs) if (ref.kind === "tag") labels.push({ kind: "tag", parts: [{ kind: "tag", name: ref.name, text: fit(ref.name, LABEL.MAX), icon: true }] });
  for (const label of labels) {
    for (const part of label.parts) part.width = partWidth(part, char);
    label.width = label.parts.reduce((n, p) => n + p.width, 2);
  }
  return labels;
}

// The label part at `x` in a row whose labels start at `start` and are cut off at `limit`.
export function hitLabel(labels, x, start, limit = Infinity) {
  if (x >= limit) return null;
  let left = start;
  for (const label of labels ?? []) {
    left += LABEL.GAP;
    if (x >= left && x < left + label.width) {
      let at = left + 1;
      for (const part of label.parts) {
        if (x < at + part.width) return { label, part };
        at += part.width;
      }
      return { label, part: label.parts[label.parts.length - 1] };
    }
    left += label.width;
  }
  return null;
}

const section = (...items) => items.filter(Boolean);
const item = (label, icon, action) => ({ label, icon, action });

// The right-click menu for a change or a label part. Sections are separated.
export function menuFor(target, ctx) {
  const c = target.commit, rev = revOf(c), short = c.prefix + c.rest;
  let sections;
  if (target.kind === "bookmark") {
    const name = target.name;
    sections = [
      section(item(`New change on ${name}`, "plus", { type: "new", rev, short: name })),
      section(ctx.remotes.length > 0 && item("Push bookmark…", "push", { type: "push", name }),
        item("Rename bookmark…", "rename", { type: "renameBookmark", name }),
        item("Delete bookmark…", "trash", { type: "deleteBookmark", name })),
      section(item("Copy bookmark name", "copy", { type: "copy", text: name })),
    ];
  } else if (target.kind === "remote") {
    const r = target.ref;
    sections = [
      section(item(`New change on ${r.name}`, "plus", { type: "new", rev, short: r.name })),
      section(r.tracked ? item("Stop tracking", "cloud", { type: "untrack", bookmark: r.bookmark, remote: r.remote, name: r.name })
        : item("Track bookmark", "cloud", { type: "track", bookmark: r.bookmark, remote: r.remote, name: r.name })),
      section(item("Copy bookmark name", "copy", { type: "copy", text: r.name })),
    ];
  } else if (target.kind === "workspace") {
    const w = target.ref;
    sections = [
      section(w.path && !w.current && item("Show its space", "folder", { type: "space", name: w.name, path: w.path }),
        item(`New change on ${w.name}@`, "plus", { type: "new", rev, short: `${w.name}@` })),
      section(w.path && item("Copy workspace path", "copy", { type: "copy", text: w.path })),
      // jj never removes the main workspace, which keeps the name "default".
      section(!w.current && w.name !== "default" && item("Remove workspace…", "trash", { type: "removeWorkspace", name: w.name, path: w.path })),
    ];
  } else if (target.kind === "tag") {
    sections = [
      section(item(`New change on ${target.name}`, "plus", { type: "new", rev, short: target.name })),
      section(item("Copy tag name", "copy", { type: "copy", text: target.name })),
    ];
  } else {
    const mutable = !c.immutable && !c.root;
    sections = [
      section(mutable && !c.wc && !target.workspace && item("Edit this change", "commit", { type: "edit", rev, short }),
        item("New change on top", "plus", { type: "new", rev, short }),
        mutable && item("Describe…", "rename", { type: "describe", rev, short })),
      section(mutable && target.squashable && item("Squash into parent…", "merge", { type: "squash", rev, short, useDest: Boolean(target.bothDescribed) }),
        !c.wc && ctx.wcChange && item("Rebase @ onto this…", "rebase", { type: "rebase", rev, short }),
        mutable && item("Abandon…", "trash", { type: "abandon", rev, short })),
      section(!c.root && item("Set bookmark here…", "branch", { type: "setBookmark", rev, short })),
      section(item("Copy change ID", "copy", { type: "copy", text: c.change }),
        item("Copy commit ID", "copy", { type: "copy", text: c.hash }),
        item("Copy description", "copy", { type: "copyMessage", rev: c.hash })),
    ];
  }
  const out = [];
  for (const s of sections.filter((s) => s.length)) { if (out.length) out.push({ separator: true }); out.push(...s); }
  return out;
}

export const menuHeight = (items) => 10 + items.reduce((n, i) => n + (i.separator ? 9 : 30), 0);

const remoteChoice = (ctx) => ({ id: "remote", label: "Remote", value: ctx.remotes.includes("origin") ? "origin" : ctx.remotes[0],
  options: ctx.remotes.map((r) => ({ value: r, label: r })) });

// The dialog an action asks first, or null when it runs at once.
export function dialogFor(action, ctx) {
  const a = action;
  switch (a.type) {
    case "describe": return { title: "Describe change", detail: `Set the description of ${a.short}.`,
      inputs: [{ id: "message", label: "Description", value: a.message ?? "", text: true, multiline: true, optional: true }], confirm: "Describe" };
    case "squash": return { title: "Squash into parent", detail: `Move the changes in ${a.short} into its parent.${a.useDest ? " Both have descriptions: the parent's is kept." : ""}`, confirm: "Squash" };
    case "rebase": return { title: "Rebase", detail: `Rebase the branch holding @ (${ctx.wcShort}) onto ${a.short}?`, confirm: "Rebase" };
    case "abandon": return { title: "Abandon change", detail: `Abandon ${a.short}? Its descendants move onto its parent. jj undo brings it back.`, confirm: "Abandon", danger: true };
    case "setBookmark": return { title: "Set bookmark", detail: `Point a bookmark at ${a.short}.`,
      inputs: [{ id: "name", label: "Bookmark name", value: "" }], checks: [{ id: "backwards", label: "Allow moving it backwards or sideways", value: false }], confirm: "Set" };
    case "renameBookmark": return { title: "Rename bookmark", detail: `Rename ${a.name}.`, inputs: [{ id: "name", label: "New name", value: a.name }], confirm: "Rename" };
    case "deleteBookmark": return { title: "Delete bookmark", detail: `Delete ${a.name}? The next push deletes it on the remote too.`, confirm: "Delete", danger: true };
    case "removeWorkspace": return { title: "Remove workspace", detail: `Remove ${a.name}@? Its space closes and ${a.path || "its folder"} is deleted. Its changes stay in the log.`, confirm: "Remove", danger: true };
    case "push": return { title: "Push bookmark", detail: `Push ${a.name}.`, choice: remoteChoice(ctx), confirm: "Push" };
    default: return null;
  }
}

export function dialogHeight(spec) {
  const detail = spec.detail ? Math.ceil(spec.detail.length / 52) * 19 + 8 : 0;
  const inputs = (spec.inputs ?? []).reduce((n, i) => n + (i.multiline ? 170 : 66), 0);
  return Math.ceil(36 + 26 + detail + inputs + (spec.checks ?? []).length * 30
    + (spec.choice ? 24 + spec.choice.options.length * 42 : 0) + 30 + 52);
}

const values = (spec) => {
  const v = {};
  for (const i of spec?.inputs ?? []) v[i.id] = i.value ?? "";
  for (const c of spec?.checks ?? []) v[c.id] = c.value;
  if (spec?.choice) v[spec.choice.id] = spec.choice.value;
  return v;
};
export const initialValues = (action, ctx) => values(dialogFor(action, ctx));

// What's wrong with the typed values, or null. A name never reaches jj as an option.
export function validate(action, v, ctx) {
  const spec = dialogFor(action, ctx);
  for (const input of spec?.inputs ?? []) {
    const text = String(v[input.id] ?? "").trim();
    if (input.optional) continue;
    if (!text) return `${input.label} is empty.`;
    if (input.text) continue;
    if (!refName(text)) return `${input.label} isn't a valid bookmark name.`;
  }
  if (spec?.choice && !spec.choice.options.some((o) => o.value === v[spec.choice.id])) return `Pick a ${spec.choice.label.toLowerCase()}.`;
  return null;
}

// The jj commands an action runs, in order.
export function commandsFor(a, v = {}, ctx = {}) {
  const revs = ["edit", "new", "describe", "squash", "rebase", "abandon", "setBookmark"];
  const names = ["push", "renameBookmark", "deleteBookmark", "removeWorkspace"];
  if (revs.includes(a.type) && !revision(a.rev)) throw new Error("Invalid revision");
  if (names.includes(a.type) && !refName(a.name)) throw new Error(a.type === "removeWorkspace" ? "Invalid workspace name" : "Invalid bookmark name");
  if (["track", "untrack"].includes(a.type) && (!refName(a.bookmark) || !refName(a.remote))) throw new Error("Invalid remote bookmark");
  if (["setBookmark", "renameBookmark"].includes(a.type) && !refName(String(v.name ?? "").trim())) throw new Error("Invalid bookmark name");
  if (a.type === "push" && (!refName(v.remote) || !ctx.remotes?.includes(v.remote))) throw new Error("Invalid remote");
  if (a.type === "rebase" && !changeId(ctx.wcChange)) throw new Error("Invalid working copy");
  const name = String(v.name ?? "").trim(), message = String(v.message ?? "").replace(/\s+$/, "");
  const cmd = (...args) => [...WRITE, ...args];
  switch (a.type) {
    case "edit": return [cmd("edit", a.rev)];
    case "new": return [cmd("new", a.rev)];
    case "describe": return [cmd("describe", a.rev, "-m", message)];
    case "squash": return [cmd("squash", "-r", a.rev, ...(a.useDest ? ["--use-destination-message"] : []))];
    case "rebase": return [cmd("rebase", "-b", ctx.wcChange, "-o", a.rev)];
    case "abandon": return [cmd("abandon", a.rev)];
    case "setBookmark": return [cmd("bookmark", "set", name, "-r", a.rev, ...(v.backwards ? ["--allow-backwards"] : []))];
    case "renameBookmark": return [cmd("bookmark", "rename", a.name, name)];
    case "deleteBookmark": return [cmd("bookmark", "delete", `exact:${a.name}`)];
    case "removeWorkspace": return [cmd("workspace", "remove", a.name)];
    case "track": return [cmd("bookmark", "track", `${a.bookmark}@${a.remote}`)];
    case "untrack": return [cmd("bookmark", "untrack", `${a.bookmark}@${a.remote}`)];
    case "push": return [cmd("git", "push", "--remote", v.remote, "-b", `exact:${a.name}`)];
    case "fetch": return [cmd("git", "fetch", "--all-remotes")];
    case "undo": return [cmd("undo")];
    default: throw new Error("Unknown jj action");
  }
}

export function doneText(a, v = {}) {
  const name = String(v.name ?? "").trim();
  switch (a.type) {
    case "edit": return `Editing ${a.short}`;
    case "new": return `New change on ${a.short}`;
    case "describe": return `Described ${a.short}`;
    case "squash": return `Squashed ${a.short}`;
    case "rebase": return `Rebased onto ${a.short}`;
    case "abandon": return `Abandoned ${a.short}`;
    case "setBookmark": return `Set ${name} to ${a.short}`;
    case "renameBookmark": return `Renamed ${a.name} to ${name}`;
    case "deleteBookmark": return `Deleted ${a.name}`;
    case "removeWorkspace": return `Removed ${a.name}@`;
    case "track": return `Tracking ${a.name}`;
    case "untrack": return `Stopped tracking ${a.name}`;
    case "push": return `Pushed ${a.name} to ${v.remote}`;
    case "fetch": return "Fetched";
    case "undo": return "Undid last operation";
    default: return "Done";
  }
}

// jj's own words, without its hints.
export function jjError(result) {
  const lines = (result.stderr || result.stdout || "").split("\n").map((l) => l.trimEnd()).filter((l) => l && !/^Hint:/.test(l));
  return lines.slice(-6).join("\n") || `jj exited with ${result.code}`;
}

export const diffArgs = (rev) => {
  if (!revision(rev)) throw new Error("Invalid revision");
  return ["diff", ...READ, "--git", "-r", rev];
};
export const describeArgs = (rev) => {
  if (!revision(rev)) throw new Error("Invalid revision");
  return ["log", ...READ, "--no-graph", "-r", rev, "-T", "description"];
};

// The path in `diff --git a/<p> b/<p>`, which is ambiguous only when a and b differ.
function diffPath(header, lines) {
  const renamed = lines.find((l) => l.startsWith("rename to "));
  if (renamed) return renamed.slice(10);
  const n = (header.length - 5) / 2;
  if (Number.isInteger(n) && header.startsWith("a/") && header.slice(2 + n) === ` b/${header.slice(2, 2 + n)}`) return header.slice(2, 2 + n);
  const plus = lines.find((l) => l.startsWith("+++ b/")), minus = lines.find((l) => l.startsWith("--- a/"));
  return plus ? plus.slice(6) : minus ? minus.slice(6) : header;
}

// Each file in `jj diff --git`, with its status, line counts and its own diff text.
export function parseGitDiff(text) {
  const files = [];
  for (const chunk of text.split(/^diff --git /m).slice(1)) {
    const lines = chunk.replace(/\n$/, "").split("\n"), header = lines[0];
    const status = lines.some((l) => l.startsWith("new file mode")) ? "A" : lines.some((l) => l.startsWith("deleted file mode")) ? "D"
      : lines.some((l) => l.startsWith("rename from")) ? "R" : "M";
    let add = 0, del = 0, body = false;
    for (const l of lines) {
      if (l.startsWith("@@")) body = true;
      else if (body && l[0] === "+") add++;
      else if (body && l[0] === "-") del++;
    }
    files.push({ path: diffPath(header, lines), status, add, del, binary: lines.some((l) => l.startsWith("Binary files")), text: lines.join("\n") });
  }
  return files;
}

// Numbers each diff line once, so a frame only draws the rows on screen.
export function diffRows(text) {
  const all = text.replace(/\n$/, "").split("\n"), first = all.findIndex((l) => l.startsWith("@@"));
  if (first < 0) return null;
  let old = 0, next = 0;
  return all.slice(first, first + 3000).map((raw) => {
    const line = raw.length > 2000 ? raw.slice(0, 2000) + "…" : raw;
    const m = /^@@ -(\d+)(?:,\d+)? \+(\d+)/.exec(line);
    if (m) { old = +m[1]; next = +m[2]; return { kind: "@", text: line }; }
    const kind = line[0];
    if (kind === "-") return { kind, number: old++, text: line.slice(1) || " " };
    if (kind === "+") return { kind, number: next++, text: line.slice(1) || " " };
    if (kind === " ") { old++; return { kind, number: next++, text: line.slice(1) || " " }; }
    return { kind: "", text: line };
  });
}
