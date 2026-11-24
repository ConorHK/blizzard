// Fuzzy matching as fzy scores it, kept free of app imports so it can be tested alone.

const GAP_LEADING = -0.005;
const GAP_TRAILING = -0.005;
const GAP_INNER = -0.01;
const CONSECUTIVE = 1;
const AFTER_SLASH = 0.9;
const AFTER_WORD = 0.8;
const CAPITAL = 0.7;
const AFTER_DOT = 0.6;

const isWord = (c) => /[\p{L}\p{N}]/u.test(c);

function bonus(prev, c) {
  if (!isWord(c)) return 0;
  if (prev === "/") return AFTER_SLASH;
  if (prev === " " || prev === "-" || prev === "_") return AFTER_WORD;
  if (prev === ".") return AFTER_DOT;
  if (/\p{Ll}/u.test(prev) && /\p{Lu}/u.test(c)) return CAPITAL;
  return 0;
}

// Where `needle` best fits in `hay` as a subsequence: its score and the matched indexes, or null.
export function match(needle, hay) {
  // A needle with a capital matches case as typed.
  const fold = needle === needle.toLowerCase();
  const n = [...needle];
  const raw = [...hay];
  const h = fold ? raw.map((c) => c.toLowerCase()) : raw;
  if (!n.length || n.length > h.length) return null;

  const bonuses = raw.map((c, j) => bonus(j ? raw[j - 1] : "/", c));
  const ending = [];
  const best = [];
  for (let i = 0; i < n.length; i++) {
    ending.push(new Array(h.length).fill(-Infinity));
    best.push(new Array(h.length).fill(-Infinity));
    const gap = i === n.length - 1 ? GAP_TRAILING : GAP_INNER;
    let running = -Infinity;
    for (let j = 0; j < h.length; j++) {
      if (n[i] === h[j]) {
        let score = -Infinity;
        if (i === 0) score = j * GAP_LEADING + bonuses[j];
        else if (j > 0) score = Math.max(best[i - 1][j - 1] + bonuses[j], ending[i - 1][j - 1] + CONSECUTIVE);
        ending[i][j] = score;
        running = Math.max(score, running + gap);
      } else {
        running += gap;
      }
      best[i][j] = running;
    }
  }

  const score = best[n.length - 1][h.length - 1];
  if (score === -Infinity) return null;

  const positions = new Array(n.length);
  let required = false;
  for (let i = n.length - 1, j = h.length - 1; i >= 0; i--) {
    for (; j >= 0; j--) {
      if (ending[i][j] === -Infinity || !(required || ending[i][j] === best[i][j])) continue;
      required = i > 0 && j > 0 && best[i][j] === ending[i - 1][j - 1] + CONSECUTIVE;
      positions[i] = j--;
      break;
    }
  }
  return { score, positions };
}

// The items whose columns match every word of `query`, best first, each with the indexes to
// highlight per column. A word has to fit inside one column, and an empty query keeps every item.
export function rank(query, items, columns) {
  const words = query.split(/\s+/).filter(Boolean);
  const found = [];
  items.forEach((item, order) => {
    const texts = columns(item);
    const hits = texts.map(() => new Set());
    let score = 0;
    for (const word of words) {
      let best = null;
      texts.forEach((text, column) => {
        const m = match(word, text);
        if (m && (!best || m.score > best.score)) best = { ...m, column };
      });
      if (!best) return;
      score += best.score;
      best.positions.forEach((p) => hits[best.column].add(p));
    }
    found.push({ item, hits, score, order });
  });
  found.sort((a, b) => b.score - a.score || a.order - b.order);
  return found.map(({ item, hits }) => ({ item, hits }));
}
