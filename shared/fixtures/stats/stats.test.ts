// Checks the stat fixtures in this folder (#235):
// - dataset rows have the shape of pulled rows (../sync/schema),
// - every dataset's expected block equals what reference.ts computes,
// - definitions.json names every expected field, and the leak ranges match,
// - display.json strings match the display rules,
// - the datasets keep their edge cases.
// Run from this folder: deno test --frozen --allow-read=.,../sync
import { Ajv2020 } from "ajv/2020";
import { display, expectedFor, LEAK_PROFILES } from "./reference.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

const here = new URL("./", import.meta.url);
const readJson = (path: string): Json =>
  JSON.parse(Deno.readTextFileSync(new URL(path, here)));
const definitions = readJson("definitions.json");
const datasetNames = [...Deno.readDirSync(new URL("datasets/", here))]
  .map((e) => e.name).filter((n) => n.endsWith(".json")).sort();
const datasets: Record<string, Json> = Object.fromEntries(
  datasetNames.map((n) => [n, readJson(`datasets/${n}`)]),
);

// Numbers match within a relative 1e-9: the app sums doubles in fetch order.
function diff(got: Json, want: Json, path = "expected"): string[] {
  if (typeof want === "number" && typeof got === "number") {
    return Math.abs(got - want) <= 1e-9 * Math.max(1, Math.abs(want))
      ? []
      : [`${path}: got ${got}, want ${want}`];
  }
  if (Array.isArray(want)) {
    if (!Array.isArray(got) || got.length !== want.length) {
      return [
        `${path}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`,
      ];
    }
    return want.flatMap((w, i) => diff(got[i], w, `${path}[${i}]`));
  }
  if (want !== null && typeof want === "object") {
    if (got === null || typeof got !== "object" || Array.isArray(got)) {
      return [`${path}: got ${JSON.stringify(got)}, want an object`];
    }
    const keys = new Set([...Object.keys(want), ...Object.keys(got)]);
    return [...keys].flatMap((k) =>
      k in want && k in got
        ? diff(got[k], want[k], `${path}.${k}`)
        : [`${path}.${k}: ${k in want ? "missing" : "unexpected"}`]
    );
  }
  return got === want
    ? []
    : [`${path}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`];
}

// The field paths of an expected block, in the form definitions.json uses.
function fieldPaths(expected: Json): string[] {
  return Object.entries(expected).flatMap(([key, value]: [string, Json]) => {
    if (key === "lifetime") {
      return Object.keys(value).map((k) => `lifetime.${k}`);
    }
    if (key === "sessions") {
      return value.flatMap((s: Json) => Object.keys(s)).filter((k: string) =>
        k !== "id"
      ).map((k: string) => `sessions[].${k}`);
    }
    if (key === "trends") {
      return Object.values(value).flatMap((w: Json) => Object.keys(w)).map((
        k,
      ) => `trends.*.${k}`);
    }
    return [key];
  });
}

Deno.test("dataset rows have the shape of pulled rows", () => {
  const ajv = new Ajv2020({
    allErrors: true,
    strict: true,
    strictRequired: false,
  });
  for (const e of Deno.readDirSync(new URL("../sync/schema/", here))) {
    ajv.addSchema(readJson(`../sync/schema/${e.name}`));
  }
  const base =
    "https://github.com/rohanthomas1202/PokerStats/shared/fixtures/sync/schema/";
  const sessions = ajv.getSchema(`${base}pull-poker-sessions.schema.json`)!;
  const hands = ajv.getSchema(`${base}pull-hands.schema.json`)!;
  for (const [name, d] of Object.entries(datasets)) {
    if (!sessions(d.sessions)) {
      throw new Error(`${name} sessions: ${ajv.errorsText(sessions.errors)}`);
    }
    if (!hands(d.hands)) {
      throw new Error(`${name} hands: ${ajv.errorsText(hands.errors)}`);
    }
  }
});

for (const [name, d] of Object.entries(datasets)) {
  Deno.test(`${name}: expected values match the reference`, () => {
    const problems = diff(expectedFor(d), d.expected);
    if (problems.length) throw new Error(problems.join("\n"));
  });
}

Deno.test("definitions.json names every expected field, and nothing else", () => {
  const defined = Object.values(definitions.stats).flatMap((s: Json) => s.paths)
    .sort();
  const used = [
    ...new Set(Object.values(datasets).flatMap((d) => fieldPaths(d.expected))),
  ].sort();
  const undefinedFields = used.filter((p) => !defined.includes(p));
  const unusedPaths = defined.filter((p) => !used.includes(p));
  if (undefinedFields.length || unusedPaths.length) {
    throw new Error(
      `fields with no definition: ${JSON.stringify(undefinedFields)}\n` +
        `paths no dataset has: ${JSON.stringify(unusedPaths)}`,
    );
  }
  for (
    const [key, s] of Object.entries(definitions.stats) as [string, Json][]
  ) {
    for (const field of ["inputs", "formula", "display", "source"]) {
      if (typeof s[field] !== "string" || !s[field]) {
        throw new Error(
          `${key}.${field} is missing`,
        );
      }
    }
    if (!(s.display in definitions.displays)) {
      throw new Error(
        `${key}: unknown display ${s.display}`,
      );
    }
  }
});

Deno.test("leak ranges in definitions.json match the reference", () => {
  const problems = diff(
    LEAK_PROFILES,
    definitions.leak_profiles.ranges,
    "leak_profiles",
  );
  if (problems.length) throw new Error(problems.join("\n"));
});

Deno.test("display strings follow the display rules", () => {
  const cases = readJson("display.json").cases;
  const formats = new Set<string>(cases.map((c: Json) => c.format));
  for (const f of formats) {
    if (!(f in definitions.displays)) {
      throw new Error(`display.json uses undefined format ${f}`);
    }
  }
  const problems = cases.flatMap((c: Json) => {
    const got = display(c.format, c.value);
    return got === c.expected
      ? []
      : [`${c.format}(${c.value}): got ${got}, want ${c.expected}`];
  });
  if (problems.length) throw new Error(problems.join("\n"));
});

Deno.test("the datasets keep their edge cases", () => {
  // The tombstone checks look at every row. Every other check looks only at
  // live rows, so a tombstoned row can't stand in for an edge case the stats
  // never see.
  const allSessions = Object.values(datasets).flatMap((d) => d.sessions);
  const allHands = Object.values(datasets).flatMap((d) => d.hands);
  const tombstoned = new Set(
    allSessions.filter((s) => s.deleted_at).map((s) => s.id),
  );
  const sessions = allSessions.filter((s) => !s.deleted_at);
  const hands = allHands.filter((h) =>
    !h.deleted_at && !tombstoned.has(h.session_id)
  );
  const edges: Record<string, boolean> = {
    "a dataset with no rows": Object.values(datasets).some((d) =>
      !d.sessions.length && !d.hands.length
    ),
    "a tombstoned session": tombstoned.size > 0,
    "a tombstoned hand in a live session": allHands.some((h) =>
      h.deleted_at && !tombstoned.has(h.session_id)
    ),
    "hands of a tombstoned session": allHands.some((h) =>
      tombstoned.has(h.session_id)
    ),
    "an active session": sessions.some((s) => s.status === "active"),
    "an unknown status": sessions.some((s) =>
      !["active", "completed"].includes(s.status)
    ),
    "an abandoned session (completed, cash_out 0)": sessions.some((s) =>
      s.status === "completed" && s.cash_out === 0 && s.buy_in > 0
    ),
    "a zero-length session": sessions.some((s) =>
      s.status === "completed" && s.end_time === s.start_time
    ),
    "a session under the 0.01-hour guard": sessions.some((s) => {
      const hours = (Date.parse(s.end_time) - Date.parse(s.start_time)) /
        3600000;
      return s.status === "completed" && hours > 0 && hours <= 0.01;
    }),
    "custom stakes": sessions.some((s) =>
      !["0.5/1", "1/2", "1/3", "2/5", "5/10"].includes(s.stakes)
    ),
    "a nonzero tip_rake": sessions.some((s) => s.tip_rake > 0),
    "a hand with an unknown position": hands.some((h) => h.position === "?"),
    "a session with 10 or more hands": Object.values(datasets).some((d) =>
      d.expected.sessions.some((s: Json) => s.leak_finder !== null)
    ),
    "lifetime leak finder with 20 or more hands": Object.values(datasets).some((
      d,
    ) => d.expected.leak_finder !== null),
    "rolling stats with 20 or more hands": Object.values(datasets).some((d) =>
      d.expected.trends.all_time.rolling_vpip_pfr.length > 0
    ),
    "a P/L on the top bucket boundary (left out of the histogram)": Object
      .values(datasets).some((d) => {
        const t = d.expected.trends.all_time;
        return t.pl_distribution.reduce(
          (n: number, b: Json) => n + b.count,
          0,
        ) < t.session_count;
      }),
  };
  const missing = Object.entries(edges).filter(([, ok]) => !ok).map(([what]) =>
    what
  );
  if (missing.length) {
    throw new Error(`missing edge cases: ${missing.join(", ")}`);
  }
});
