// Small helpers for the canvas: opening links and short ages.
import { exec, notify, window } from "herdr";

export function openUrl(url) {
  const cmd = window()?.platform === "macos" ? "open" : "xdg-open";
  exec(cmd, [url]).catch((e) => notify({ title: "Cannot open the link", body: String(e), level: "error" }));
}

export function ago(iso) {
  const s = (Date.now() - Date.parse(iso)) / 1000;
  if (!(s >= 0)) return "";
  if (s < 3600) return `${Math.max(1, Math.round(s / 60))}m`;
  if (s < 86400) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86400)}d`;
}
