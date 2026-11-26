"""Clone Herdr's main layout and its mods with text at creeper's 15px size."""

import json
import re
import shutil
import sys
from pathlib import Path

PREFIX = "creeper-"
MODS = [
    "agents",
    "changes",
    "files",
    "machine-add",
    "menu",
    "new-menu",
    "pane",
    "picker",
    "spaces",
    "tabs",
    "workspace-chrome",
    "workspace-status",
    "worktree",
]
NAMES = "|".join(map(re.escape, MODS))
REF = re.compile(rf'\b(mod|name): "({NAMES})"')
TEXT_SIZE = re.compile(r"text_size\(([^)]*)\)")
NUMBER = re.compile(r"\b\d+(?:\.\d+)?\b")
# Creeper has only a 15px bitmap; other sizes draw nothing.
STRIKE = "15"
VIEW = re.compile(r"^export default class (\w+) extends View", re.MULTILINE)

# In a jj repo git sees a detached HEAD, so name the nearest bookmark instead.
JJ_BRANCH = """
async function jjBranch(cwd, on) {
  const revs = "heads(::@ & bookmarks())";
  const names = 'local_bookmarks.map(|b| b.name()).join(" ") ++ " "';
  const args = ["log", "--no-graph", "--ignore-working-copy", "-r", revs, "-T", names];
  const r = await exec("jj", args, { cwd, on }).catch(() => null);
  return r?.code === 0 ? (r.stdout.split(/\\s+/).find(Boolean) ?? null) : null;
}

"""
WATCH = "if (!on) this.watch(repo, cx);"
JJ_LOOKUP = 'if (info.branch === "(detached)") info.branch = await jjBranch(cwd, on);'
# In a jj repo the menus offer jj workspaces in place of git worktrees.
JJ_ROOT = 'exec("jj", ["root", "--ignore-working-copy"], { cwd: folder, on })'
MENU_CHECK = "async function checkout(folder, on) {"
MENU_JJ_CHECK = f"""
  const jj = await {JJ_ROOT}.catch(() => null);
  if (jj?.code === 0) {{
    const linked = await exec("test", ["-f", `${{jj.stdout.trim()}}/.jj/repo`], {{ on }}).catch(() => null);
    return linked?.code === 0 ? "jj-linked" : "jj";
  }}"""
MENU_GIT_ITEMS = '...(git ? [["New worktree"'
MENU_JJ_ITEMS = (
    '...(git?.startsWith("jj") ? [\n'
    '          ["New workspace", "jj-workspace", { space: tg.id, action: "new" }],\n'
    '          ["Open workspace", "jj-workspace", { space: tg.id, action: "open" }],\n'
    '          ...(git === "jj-linked" ? [["Remove workspace", "jj-workspace", { space: tg.id, action: "remove" }]] : []),\n'
    "        ] : []),\n"
    '        ...(git && !git.startsWith("jj") ? [["New worktree"'
)
MENU_CHOOSE = 'if (it[1] === "worktree") openOverlay('
# The font placeholder becomes the look's font when the mod is cloned.
JJ_DIALOG = (
    '{ mod: "jj-workspace", kind: "dialog", width: OPEN ? 560 : 460, height: OPEN ? 480 : 280,'
    f' props: {{ ...ARGS, font: "@font@", size: {STRIKE} }} }}'
)
MENU_JJ_CHOOSE = (
    'if (it[1] === "jj-workspace") openOverlay('
    + JJ_DIALOG.replace("OPEN", 'it[2].action === "open"').replace("ARGS", "it[2]")
    + ");\n    else "
    + MENU_CHOOSE
)
MENU_ICON = 'command === "worktree" ?'
NEW_MENU_JJ_ROW = """
    if (this.jj && id.startsWith("worktree")) {
      const open = id === "worktree-open";
      const args = { space: spaces().find((s) => s.active)?.id, folder: panes().find((p) => p.focused)?.cwd, action: open ? "open" : "new" };
      name = open ? "Open workspace\\u2026" : "New workspace\\u2026";
      action = () => openOverlay(DIALOG);
    }""".replace("DIALOG", JJ_DIALOG.replace("OPEN", "open").replace("ARGS", "args"))
NEW_MENU_INIT = "    this.handle.focus();\n    cx.spawn(async cx => {"
NEW_MENU_JJ = (
    "    const folder = panes().find((p) => p.focused)?.cwd;\n"
    "    const on = machine;\n"
    "    if (folder) cx.spawn(async (cx) => {\n"
    f"      const r = await {JJ_ROOT}.catch(() => null);\n"
    "      this.jj = r?.code === 0;\n      cx.notify();\n    });\n"
)
NEW_MENU_ROW = 'row(id, icon, name, action, hint = "", enabled = true) {'
PANE_NAME = (
    ".child(div().flex_none().truncate().max_w(260).font_medium()"
    ".text_color(t.foreground).child(name))"
)
# ogham labels a pi session's terminal with its task's link; the header opens it.
PANE_LINK = """function linkLabel(link) {
  try {
    const url = new URL(link);
    const parts = url.pathname.split("/").filter(Boolean);
    return decodeURIComponent(parts[parts.length - 1] ?? url.host);
  } catch {
    return "";
  }
}

export default class Pane extends View {"""
PANE_LINK_VAR = """    const pane = p.pane;
    const labels = linkHerdr.terminals().find((x) => x.address === p.terminal)?.labels ?? {};
    const link = labels["ogham.link"];
    const linked = typeof link === "string" && link.startsWith("https://");
    const linkText = labels["ogham.title"] || linkLabel(link);"""
PANE_LINK_CHIP = """
      .when(linked, (el) => el.child(div().id(`ph-link-${pane}`).flex_shrink(1).min_w_0().max_w(560).truncate().px(6)
        .border(1).border_color(t.accent).text_color(t.accent).hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => {
          cx.stop_propagation();
          linkHerdr.exec(linkHerdr.window()?.platform === "macos" ? "open" : "xdg-open", [link]);
        })
        .child(linkText)))"""
PATCHES = {
    "menu": [
        (MENU_CHECK, MENU_CHECK + MENU_JJ_CHECK),
        (MENU_GIT_ITEMS, MENU_JJ_ITEMS),
        (MENU_CHOOSE, MENU_JJ_CHOOSE),
        (MENU_ICON, 'command === "worktree" || command === "jj-workspace" ?'),
    ],
    "new-menu": [
        ("knownAgents, run,", "knownAgents, exec, run,"),
        (
            NEW_MENU_INIT,
            NEW_MENU_INIT.replace("    cx.spawn", NEW_MENU_JJ + "    cx.spawn"),
        ),
        (
            NEW_MENU_ROW,
            NEW_MENU_ROW + NEW_MENU_JJ_ROW,
        ),
    ],
    "spaces": [
        ("export default class", JJ_BRANCH + "export default class"),
        (WATCH, f"{JJ_LOOKUP}\n      {WATCH}"),
    ],
    "tabs": [
        (".h(29).px(10).gap(7).rounded(7)", ".h(29).px(10).gap(7).rounded(0)"),
    ],
    "pane": [
        ("export default class Pane extends View {", PANE_LINK),
        ("    const pane = p.pane;", PANE_LINK_VAR),
        (PANE_NAME, PANE_NAME + PANE_LINK_CHIP),
    ],
}

# Imports the patches need, put first in the file once every patch matched; a namespace
# import never clashes with the names the shipped import line grows.
IMPORTS = {"pane": 'import * as linkHerdr from "herdr";\n'}


def rewrite(source: str) -> str:
    """Point mod references at the clones and set every text size to 15."""
    source = REF.sub(lambda m: f'{m.group(1)}: "{PREFIX}{m.group(2)}"', source)
    return TEXT_SIZE.sub(
        lambda m: f"text_size({NUMBER.sub(STRIKE, m.group(1))})", source
    )


def patch(name: str, source: str) -> str:
    """Apply all of this mod's patches, or none if any no longer matches once."""
    patches = PATCHES.get(name, [])
    if any(source.count(old) != 1 for old, _ in patches):
        # A mod half patched can call what it never imported.
        print(f"herdr-creeper: {name} changed, skipped its patches")
        return source
    for old, new in patches:
        source = source.replace(old, new)
    return IMPORTS.get(name, "") + source


def set_font(source: str, font: str) -> str:
    """Wrap the mod's view so its whole tree uses the font at its size."""
    view = VIEW.search(source)
    if not view:
        return source
    wrapper = (
        f"\nexport default class extends {view.group(1)} {{\n"
        "  render(cx) {\n"
        "    const el = super.render(cx);\n"
        f'    return typeof el?.font_family === "function" ? el.font_family("{font}").text_size({STRIKE}) : el;\n'
        "  }\n"
        "}\n"
    )
    return VIEW.sub(r"class \1 extends View", source) + wrapper


def clone_mod(mods: Path, name: str, font: str) -> None:
    """Copy one shipped mod beside it under the prefixed name."""
    dst = mods / f"{PREFIX}{name}"
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(mods / name, dst)
    for js in dst.rglob("*.js"):
        js.write_text(rewrite(js.read_text()))
    main = dst / "main.js"
    patched = patch(name, main.read_text()).replace("@font@", font)
    main.write_text(set_font(patched, font))


def rename_mods(node: object) -> object:
    """Point every layout block at the cloned mods."""
    if isinstance(node, dict):
        return {
            k: f"{PREFIX}{v}" if k == "mod" and v in MODS else rename_mods(v)
            for k, v in node.items()
        }
    if isinstance(node, list):
        return [rename_mods(v) for v in node]
    return node


def square(node: object) -> object:
    """Give every rounded layout node square corners."""
    if isinstance(node, dict):
        return {k: 0 if k == "radius" else square(v) for k, v in node.items()}
    if isinstance(node, list):
        return [square(v) for v in node]
    return node


def pad_hidden(node: object) -> object:
    """Give each hidden container with one child a zero-size spacer as a second."""
    if isinstance(node, list):
        return [pad_hidden(v) for v in node]
    if not isinstance(node, dict):
        return node
    node = {k: pad_hidden(v) for k, v in node.items()}
    kids = node.get("children")
    if node.get("hidden") and isinstance(kids, list) and len(kids) == 1:
        node["children"] = [*kids, spacer(node["id"])]
    return node


def spacer(owner: str) -> dict:
    """Return a zero-size block that draws nothing."""
    return {
        "id": f"{owner}-spacer",
        "type": "block",
        "size": {"px": 0},
        "content": {"mod": "spacer"},
    }


def main() -> int:
    """Write the clones into the Herdr home given as the first argument."""
    home, font = Path(sys.argv[1]), sys.argv[2]
    mods = home / "mods"
    missing = [m for m in MODS if not (mods / m / "main.js").exists()]
    if missing:
        print(f"herdr-creeper: start Herdr once first, missing {missing}")
        return 0
    for name in MODS:
        clone_mod(mods, name, font)
    layout = pad_hidden(
        square(rename_mods(json.loads((home / "layouts" / "main.json").read_text())))
    )
    layout["terminal_menu"] = f"{PREFIX}menu"
    # A zero-size block keeps the workers mod alive to grid sub-agents.
    sidebar = next(c for c in layout["children"] if c.get("id") == "sidebar")
    sidebar["children"].append(
        {
            "id": "workers-watch",
            "type": "block",
            "size": {"px": 0},
            "content": {"mod": "workers", "props": {"layout": "creeper"}},
        }
    )
    (home / "layouts" / "creeper.json").write_text(json.dumps(layout, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
