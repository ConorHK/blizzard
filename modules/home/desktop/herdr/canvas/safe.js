// Checks on what a canvas may do, kept free of app imports so they can be tested alone.
export const MAX_SEND = 2000;

// Only https links open; anything else (file:, javascript:, a custom scheme) is refused.
export function safeUrl(text) {
  try {
    const url = new URL(String(text));
    return url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}

// What a button shows besides its label, so its effect is never hidden behind a friendly name.
export function effect(item) {
  if (item.link) {
    const url = safeUrl(item.link);
    return url ? { kind: "link", text: url.host, ok: true } : { kind: "link", text: "blocked: not an https link", ok: false };
  }
  if (typeof item.send === "string") {
    if (item.send.length > MAX_SEND) return { kind: "send", text: `blocked: over ${MAX_SEND} characters`, ok: false };
    return { kind: "send", text: `sends: ${clip(item.send, 80)}`, ok: true };
  }
  return { kind: "none", text: "", ok: false };
}

// For display only; what is sent is never shortened.
export function clip(text, max) {
  const one = String(text).replace(/\s+/g, " ").trim();
  return one.length > max ? `${one.slice(0, max - 1)}\u2026` : one;
}
