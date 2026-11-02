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
# Git worktrees make no sense in a jj repo, so the menus leave them out there.
JJ_ROOT = 'exec("jj", ["root", "--ignore-working-copy"], { cwd: folder, on })'
MENU_CHECK = "async function checkout(folder, on) {"
NEW_MENU_INIT = "    this.handle.focus();\n    cx.spawn(async cx => {"
NEW_MENU_JJ = (
    "    const folder = panes().find((p) => p.focused)?.cwd;\n"
    "    const on = machine;\n"
    "    if (folder) cx.spawn(async (cx) => {\n"
    f"      const r = await {JJ_ROOT}.catch(() => null);\n"
    "      this.jj = r?.code === 0;\n      cx.notify();\n    });\n"
)
NEW_MENU_ROW = 'row(id, icon, name, action, hint = "", enabled = true) {'
PATCHES = {
    "menu": [
        (
            MENU_CHECK,
            f"{MENU_CHECK}\n  if ((await {JJ_ROOT}).code === 0) return null;",
        ),
    ],
    "new-menu": [
        ("knownAgents, run,", "knownAgents, exec, run,"),
        (
            NEW_MENU_INIT,
            NEW_MENU_INIT.replace("    cx.spawn", NEW_MENU_JJ + "    cx.spawn"),
        ),
        (
            NEW_MENU_ROW,
            f'{NEW_MENU_ROW}\n    if (this.jj && id.startsWith("worktree")) return div();',
        ),
    ],
    "spaces": [
        ("export default class", JJ_BRANCH + "export default class"),
        (WATCH, f"{JJ_LOOKUP}\n      {WATCH}"),
    ],
    "tabs": [
        (".h(29).px(10).gap(7).rounded(7)", ".h(29).px(10).gap(7).rounded(0)"),
    ],
}


def rewrite(source: str) -> str:
    """Point mod references at the clones and set every text size to 15."""
    source = REF.sub(lambda m: f'{m.group(1)}: "{PREFIX}{m.group(2)}"', source)
    return TEXT_SIZE.sub(
        lambda m: f"text_size({NUMBER.sub(STRIKE, m.group(1))})", source
    )


def patch(name: str, source: str) -> str:
    """Apply this mod's patches, each of which must match exactly once."""
    for old, new in PATCHES.get(name, []):
        if source.count(old) != 1:
            print(f"herdr-creeper: {name} changed, skipped a patch")
            continue
        source = source.replace(old, new)
    return source


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
    main.write_text(set_font(patch(name, main.read_text()), font))


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
    layout = square(
        rename_mods(json.loads((home / "layouts" / "main.json").read_text()))
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
