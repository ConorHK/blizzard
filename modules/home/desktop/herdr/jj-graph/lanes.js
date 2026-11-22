// Lays changes out on lanes. Changes come newest first, every child before its
// parents (jj log's order). A lane is a column waiting for one commit and keeps
// its column until that commit arrives, so lines bend only where changes fork or
// merge. Parents in `commit.indirect` are drawn dashed, as jj draws elided
// ancestry, and `commit.elided` adds a dashed stub for ancestors not shown.
//
// Each row gets the commit's lane and its segments [fromLane, fromY, toLane,
// toY, colorLane, dashed], with y 0 = top of the row, 0.5 = the dot, 1 = bottom.
export function layoutLanes(commits) {
  const lanes = [], dashed = [];
  const free = () => { const i = lanes.indexOf(null); return i < 0 ? lanes.length : i; };
  let width = 1;
  const rows = commits.map((commit) => {
    const before = lanes.slice(), wasDashed = dashed.slice(), segments = [];
    const indirect = commit.indirect ?? new Set();
    let lane = before.indexOf(commit.hash);
    if (lane < 0) { lane = free(); lanes[lane] = commit.hash; dashed[lane] = false; }
    before.forEach((hash, j) => {
      if (hash === null || hash === undefined) return;
      if (hash === commit.hash) {
        segments.push([j, 0, lane, 0.5, j, Boolean(wasDashed[j])]);
        if (j !== lane) { lanes[j] = null; dashed[j] = false; }
      } else segments.push([j, 0, j, 1, j, Boolean(wasDashed[j])]);
    });
    const [first, ...rest] = commit.parents;
    lanes[lane] = first ?? null;
    dashed[lane] = Boolean(first && indirect.has(first));
    if (first) segments.push([lane, 0.5, lane, 1, lane, dashed[lane]]);
    for (const parent of rest) {
      let k = lanes.indexOf(parent);
      if (k < 0) { k = free(); lanes[k] = parent; dashed[k] = indirect.has(parent); }
      segments.push([lane, 0.5, k, 1, k, dashed[k]]);
    }
    if (commit.elided && !first) segments.push([lane, 0.5, lane, 0.95, lane, true]);
    width = Math.max(width, before.length, lanes.length);
    while (lanes.length && lanes[lanes.length - 1] === null) { lanes.pop(); dashed.length = lanes.length; }
    return { lane, segments };
  });
  return { rows, width };
}
