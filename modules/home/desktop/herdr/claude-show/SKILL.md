---
name: herdr-show
description: Show a page beside this session in Herdr's canvas sidebar (ctrl-shift-g) with herdr-show. Use to put a document, screenshot, diagram, table or status board in front of the user while you keep working.
---

# herdr-show

Pipe a page to `herdr-show`. Each call replaces the last page; `herdr-show --clear` empties it.

```bash
herdr-show <<'EOF'
{"title": "Deploy status", "blocks": [
  {"type": "stats", "items": [{"label": "hosts", "value": "4/5", "tone": "warn"}]},
  {"type": "table", "columns": ["host", "state"], "rows": [["puca", "ok"], ["sluagh", "failed"]]},
  {"type": "doc", "path": "docs/deploy.md"}
]}
EOF
```

Blocks, top to bottom:

- `heading {text}`, `markdown {text}`, `code {text, language}`
- `doc {path}`: a markdown or text file, or a source file shown as code (256 KB max)
- `image {path, text}`: a PNG, JPEG, GIF, WebP or SVG file with an optional caption (5 MB max)
- `stats {items: [{label, value, tone}]}`
- `table {columns, rows}`
- `list {items: [{text, detail, link, tone}]}`: links must be https
- `progress {label, value}`: value from 0 to 1

Tones: `good`, `bad`, `warn`, `info`, `muted`.

Paths are read when you run the command, so run it again to show a newer version.
The canvas opens by itself while the user has this session focused. It only displays:
the user answers in the session. It works only inside a Herdr terminal.
