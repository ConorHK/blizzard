// Line search with ripgrep's smart case, kept free of app imports so it can be tested alone.

// The query as a regular expression: any case unless it has a capital outside an escape, and
// with Unicode classes such as \p{L} where the expression allows them. A query that is not a
// valid expression, as a half-typed bracket is not, is taken letter for letter.
export function pattern(query) {
  if (!query) return null;
  const literal = query.replace(/\\[pP]\{[^}]*\}|\\./g, "");
  const flags = literal === literal.toLowerCase() ? "i" : "";
  for (const unicode of ["u", ""]) {
    try {
      return new RegExp(query, flags + unicode);
    } catch {
      // The next, looser reading of the query is tried.
    }
  }
  return new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), flags);
}

// At most `limit` of the lines `re` matches, newest first, each with where its first match sits.
export function search(re, lines, limit) {
  const found = [];
  for (let line = lines.length - 1; line >= 0 && found.length < limit; line--) {
    const m = re.exec(lines[line]);
    if (m?.[0]) found.push({ line, start: m.index, end: m.index + m[0].length });
  }
  return found;
}

// A line cut to begin near its match, so the match shows in a narrow column.
export function excerpt(line, start, end, lead = 16) {
  const indent = line.length - line.trimStart().length;
  const cut = start - indent > lead;
  const from = cut ? start - lead : indent;
  const mark = cut ? "..." : "";
  return { text: mark + line.slice(from), start: start - from + mark.length, end: end - from + mark.length };
}
