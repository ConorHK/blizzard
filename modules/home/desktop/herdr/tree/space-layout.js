// Each space keeps the layout it last showed, so a view stays with its space.
import { run, setShared, shared } from "herdr";

const KEY = "views.spaceLayouts";
// Long enough for a new space on another machine to show up.
const CARRY_MS = 30000;
// Until a switch lands, the layout it leaves is not the space's choice.
const SWITCH_MS = 2000;

const load = () => shared(KEY) ?? { space: null, layouts: {} };

// A view hands its layout to the space it starts pi in; with no id, the next space of that name.
export function carryLayout(name, machine, id) {
  const s = load();
  const layout = shared("layout");
  if (id) setShared(KEY, { ...s, layouts: { ...s.layouts, [id]: layout } });
  else setShared(KEY, { ...s, carry: { name, machine: machine ?? null, layout, until: Date.now() + CARRY_MS } });
}

// Showing a space shows its layout; switching layouts records it for the shown space.
export function followSpace(spaces, follow) {
  const { home, views = [] } = follow ?? {};
  const shown = shared("layout");
  const space = spaces.find((p) => p.active);
  const known = (name) => name === home || views.includes(name);
  if (!home || !space || !known(shown)) return;
  const s = load();
  const layouts = { ...s.layouts };
  if (space.id !== s.space) {
    const c = s.carry;
    const carried = Boolean(c) && c.until > Date.now() && c.name === space.name && c.machine === space.machine;
    if (carried) layouts[space.id] = c.layout;
    let want = s.space == null ? shown : (layouts[space.id] ?? home);
    if (!known(want)) want = home;
    if (want === home) delete layouts[space.id];
    else layouts[space.id] = want;
    const pending = want === shown ? null : { want, until: Date.now() + SWITCH_MS };
    setShared(KEY, { space: space.id, layouts, carry: carried ? null : s.carry, pending });
    if (pending) run("layout.switch", { name: want });
    return;
  }
  if (s.pending && s.pending.want !== shown && s.pending.until > Date.now()) return;
  if ((layouts[space.id] ?? home) === shown && !s.pending) return;
  if (shown === home) delete layouts[space.id];
  else layouts[space.id] = shown;
  setShared(KEY, { ...s, layouts, pending: null });
}
