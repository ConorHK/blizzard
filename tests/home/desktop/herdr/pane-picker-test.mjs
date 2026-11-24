import assert from "node:assert/strict";
import { test } from "node:test";
import { match, rank } from "./fuzzy.mjs";

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
  assert.deepEqual(match("b", "🔌b").positions, [1]);
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
