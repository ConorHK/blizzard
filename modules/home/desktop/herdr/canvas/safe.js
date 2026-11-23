// Checks on what a canvas may do, kept free of app imports so they can be tested alone.
// Only https links open; anything else (file:, javascript:, a custom scheme) is refused.
export function safeUrl(text) {
  try {
    const url = new URL(String(text));
    return url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}
