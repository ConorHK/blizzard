// The tab strip over the sidebar's lower stack, one tab per block that downstream modules add.
import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { layout, props, run, theme } from "herdr";

const find = (node, id) => (!node ? null : node.id === id ? node : (node.children ?? []).reduce((hit, c) => hit ?? find(c, id), null));

export default class SidebarTabs extends View {
  init() {}

  render() {
    const t = theme(), { stack, tabs = [], font, size } = props() ?? {};
    const active = find(layout(), stack)?.active ?? tabs[0]?.id;
    return h_flex().size_full().px(8).gap(2).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .text_size(size ?? 12.5).when(Boolean(font), (e) => e.font_family(font))
      .children(tabs.map((tab) => {
        const on = tab.id === active;
        return div().id(`sidebar-tab-${tab.id}`).h(22).px(8).flex().items_center().rounded(5).cursor_pointer()
          .bg(on ? t.selected : t.chrome).text_color(on ? t.foreground : t.muted).hover((s) => s.bg(t.hover))
          .on_click(() => run("layout.select", { stack, child: tab.id })).child(tab.title);
      }));
  }
}
