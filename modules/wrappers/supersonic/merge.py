"""Lay the managed settings over Supersonic's own config.toml."""

import os
import sys
import tomllib
from pathlib import Path

import tomli_w


def merge(base: dict, over: dict) -> dict:
    """Return base with every key in over set, recursing into tables."""
    for key, value in over.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
    return base


def main() -> None:
    """Merge the managed config into config.toml and link in the theme."""
    managed = tomllib.loads(Path(sys.argv[1]).read_text())
    theme = Path(sys.argv[2])
    home = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    target = Path(home) / "supersonic" / "config.toml"
    current = tomllib.loads(target.read_text()) if target.exists() else {}
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(tomli_w.dumps(merge(current, managed)))

    link = target.parent / "themes" / managed["Theme"]["ThemeFile"]
    link.parent.mkdir(exist_ok=True)
    link.unlink(missing_ok=True)
    link.symlink_to(theme)


if __name__ == "__main__":
    main()
