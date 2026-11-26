// The right-click menu, opened as a popup at the pointer with props
// { role: "menu", target, ctx }. Styled like Herdr's own menu.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, notify, theme, exec } from "herdr";
import { menuFor, describeArgs, jjError } from "./jj.js";
import { perform, openDialog, showSpace } from "./act.js";

export const icon = (name) => `mods/jj-graph/icons/${name}.svg`;

async function readDescription(rev, ctx) {
  const r = await exec("jj", describeArgs(rev), { cwd: ctx.root, on: ctx.on });
  if (r.code !== 0) throw new Error(jjError(r));
  return r.stdout.replace(/\n$/, "");
}

export class Menu {
  init(cx) {
    const { target, ctx } = props();
    this.items = menuFor(target, ctx);
    this.at = -1;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  choose(i, cx) {
    const it = this.items[i], { overlay, ctx } = props();
    if (!it || it.separator || this.busy !== undefined) return;
    const a = it.action;
    if (a.type === "copy") {
      cx.write_to_clipboard(a.text);
      closeOverlay(overlay);
      notify({ title: "Copied", body: a.text, level: "success", timeout: 2000 });
    } else if (a.type === "space") {
      closeOverlay(overlay);
      showSpace(a, ctx.on);
    } else if (a.type === "copyMessage" || a.type === "describe") {
      // Both need the full description, which the log only has the first line of.
      this.busy = i;
      cx.spawn(async (cx) => {
        try {
          const text = await readDescription(a.rev, ctx);
          if (a.type === "describe") openDialog({ ...a, message: text }, ctx);
          else { cx.write_to_clipboard(text); notify({ title: "Description copied", level: "success", timeout: 2000 }); }
          closeOverlay(overlay);
        } catch (e) {
          this.busy = undefined;
          notify({ title: "Couldn't read the description", body: String(e?.message ?? e), level: "error" });
          cx.notify();
        }
      });
    } else if (openDialog(a, ctx)) {
      closeOverlay(overlay);
    } else {
      // Runs here, then closes: a closed popup's tasks would be cancelled.
      this.busy = i;
      cx.spawn(async (cx) => { await perform(a, {}, ctx); closeOverlay(overlay); cx.notify(); });
    }
    cx.notify();
  }

  move(step) {
    const n = this.items.length;
    for (let k = 1; k <= n; k++) {
      const i = (this.at + step * k + n * 2) % n;
      if (!this.items[i].separator) { this.at = i; return; }
    }
  }

  render() {
    const t = theme();
    const danger = (it) => ["abandon", "deleteBookmark", "removeWorkspace"].includes(it.action.type);
    const { font, size } = props().ctx?.text ?? {};
    return v_flex().id("jj-graph-menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(size ?? 12.8).when(Boolean(font), (e) => e.font_family(font))
      .on_key_down((e, cx) => {
        if (e.key === "down") this.move(1);
        else if (e.key === "up") this.move(-1);
        else if (e.key === "enter") this.choose(this.at, cx);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .children(this.items.map((it, i) => it.separator
        ? div().mx(7).my(4).h(1).flex_none().bg(t.border)
        : h_flex().id(`jm-${i}`).h(30).flex_none().px(8).gap(9).rounded(7).items_center().cursor_pointer()
          .text_color(danger(it) ? t.ansi1 : t.foreground)
          .when(i === this.at || this.busy === i, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => this.choose(i, cx))
          .child(svg(icon(it.icon)).size(14).flex_none().text_color(danger(it) ? t.ansi1 : t.muted))
          .child(div().flex_1().min_w(0).truncate().child(this.busy === i ? "Working…" : it.label))));
  }
}
