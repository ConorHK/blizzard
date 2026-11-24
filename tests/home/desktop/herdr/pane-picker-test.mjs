import assert from "node:assert/strict";
import { test } from "node:test";
import { match, rank } from "./fuzzy.mjs";
import { excerpt, pattern, search } from "./grep.mjs";

const marked = (needle, hay) => {
  const m = match(needle, hay);
  return m && [...hay].map((c, i) => (m.positions.includes(i) ? `[${c}]` : c)).join("");
};

test("match needs the letters in order", () => {
  assert.equal(match("xyz", "abc"), null);
  assert.equal(match("ba", "abc"), null);
  assert.equal(match("abcd", "abc"), null);
  assert.equal(match("", "abc"), null);
});

test("match prefers word starts and runs", () => {
  assert.equal(marked("cp", "Control Plane / healthcheck"), "[C]ontrol [P]lane / healthcheck");
  assert.equal(marked("tri", "matrix / Triage"), "matrix / [T][r][i]age");
  assert.equal(marked("60810", "Triage / DPSTT-60810"), "Triage / DPSTT-[6][0][8][1][0]");
  assert.ok(match("cp", "Control Plane").score > match("cp", "scp copy").score);
});

test("match follows the case of a capital", () => {
  assert.equal(marked("pi", "Herdr / Pi"), "Herdr / [P][i]");
  assert.equal(marked("Pi", "Herdr / Pi"), "Herdr / [P][i]");
  assert.equal(match("Pi", "herdr / pi"), null);
});

test("match counts characters, not code units", () => {
  assert.deepEqual(match("b", "\u{1F50C}b").positions, [1]);
});

const panes = [
  ["Herdr / 1", "Herdr-1 - Knoconor-nix", "Pi", "~/Repositories/Knoconor-nix"],
  ["Herdr / Pi", "nvim", "Neovim", "~/Repositories/blizzard"],
  ["Triage / DPSTT-60644", "investigate canaries", "Pi", "/workplace/site"],
  ["review / 1", "~/r/site", "fish", "/workplace/site"],
];
const names = (query) => rank(query, panes, (p) => p).map((r) => r.item[0]);

test("rank keeps every item in order for an empty query", () => {
  assert.deepEqual(names(""), panes.map((p) => p[0]));
  assert.deepEqual(names("  "), panes.map((p) => p[0]));
});

test("rank needs every word, each inside one column", () => {
  assert.deepEqual(names("canaries pi"), ["Triage / DPSTT-60644"]);
  assert.deepEqual(names("blizzard"), ["Herdr / Pi"]);
  assert.deepEqual(names("canaries fish"), []);
  // "her" ends one column and "vim" starts the next, so no one column holds "hervim".
  assert.deepEqual(names("hervim"), []);
});

test("rank puts the better match first", () => {
  assert.equal(names("tri pi")[0], "Triage / DPSTT-60644");
  assert.deepEqual(names("site").slice(0, 2), ["review / 1", "Triage / DPSTT-60644"]);
});

test("rank marks the matched characters per column", () => {
  const [row] = rank("rev fish", panes, (p) => p);
  assert.equal(row.item[0], "review / 1");
  assert.deepEqual(row.hits.map((s) => [...s]), [[0, 1, 2], [], [0, 1, 2, 3], []]);
});

test("pattern is smart about case and survives a bad expression", () => {
  assert.equal(pattern(""), null);
  assert.ok(pattern("error").test("An ERROR here"));
  assert.ok(!pattern("Error").test("an error here"));
  assert.ok(pattern("\\S+rror").test("ERROR"));
  assert.ok(pattern("e(r").test("the(re"));
  assert.ok(pattern("fo+\\d").test("xfoo7"));
});

test("pattern knows Unicode classes, and falls back for looser escapes", () => {
  assert.ok(pattern("^\\p{L}+$").test("\u00e9t\u00e9"));
  assert.ok(!pattern("^\\p{L}+$").test("1234"));
  assert.ok(pattern("\\p{Lu}rror").test("Error"));
  // The class name's capitals do not make the search case sensitive.
  assert.ok(pattern("\\p{L}rror").test("ERROR"));
  assert.ok(pattern("^.$").test("\u{1F50C}"));
  assert.ok(pattern("a\\-b").test("a-b"));
});

test("search lists the newest matching lines first", () => {
  const lines = ["an error", "fine", "", "Error: two", "ok"];
  assert.deepEqual(search(pattern("error"), lines, 9), [
    { line: 3, start: 0, end: 5 },
    { line: 0, start: 3, end: 8 },
  ]);
  assert.deepEqual(search(pattern("error"), lines, 1), [{ line: 3, start: 0, end: 5 }]);
  assert.deepEqual(search(pattern("x*"), lines, 9), []);
});

test("excerpt begins a long line near its match", () => {
  assert.deepEqual(excerpt("    short error", 10, 15), { text: "short error", start: 6, end: 11 });
  const long = `${"x".repeat(40)} error here`;
  assert.deepEqual(excerpt(long, 41, 46), { text: `...${"x".repeat(15)} error here`, start: 19, end: 24 });
});
