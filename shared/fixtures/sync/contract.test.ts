// Checks the sync contract in this folder (#233):
// - every example in examples/<schema>/valid passes schema/<schema>.schema.json,
// - every example in examples/<schema>/invalid fails it with the error listed
//   in examples/expected-errors.json,
// - columns.json matches the schema and docs/design/1.1-sync.md sections 2 and 9.4.
// strictRequired is off because it does not follow $ref, and required lists
// here name properties defined in common.schema.json.
// Run from this folder: deno test --allow-read=.,../../../docs
import { Ajv2020, type ErrorObject } from "ajv/2020";

// deno-lint-ignore no-explicit-any
type Json = any;

const here = new URL("./", import.meta.url);
const readJson = (path: string): Json =>
  JSON.parse(Deno.readTextFileSync(new URL(path, here)));
const list = (path: string): string[] => {
  try {
    return [...Deno.readDirSync(new URL(path, here))].map((e) => e.name).filter(
      (n) => n.endsWith(".json"),
    ).sort();
  } catch (e) {
    if (e instanceof Deno.errors.NotFound) return [];
    throw e;
  }
};
const sameSet = (what: string, got: string[], want: string[]) => {
  const g = [...got].sort(), w = [...want].sort();
  if (JSON.stringify(g) !== JSON.stringify(w)) {
    throw new Error(
      `${what}:\n  got  ${JSON.stringify(g)}\n  want ${JSON.stringify(w)}`,
    );
  }
};

const ajv = new Ajv2020({
  allErrors: true,
  strict: true,
  strictRequired: false,
});
const schemaNames = list("schema/").map((n) =>
  n.replace(/\.schema\.json$/, "")
);
const schemas: Record<string, Json> = {};
for (const name of schemaNames) {
  schemas[name] = readJson(`schema/${name}.schema.json`);
  ajv.addSchema(schemas[name]);
}
const validator = (name: string) => ajv.getSchema(schemas[name].$id)!;
const expected: Record<string, { instancePath: string; keyword: string }> =
  readJson("examples/expected-errors.json");
const exampleDirs = [...Deno.readDirSync(new URL("examples/", here))].filter((
  e,
) => e.isDirectory).map((e) => e.name);

Deno.test("every example folder has a schema, and every message schema has examples", () => {
  sameSet(
    "example folders",
    exampleDirs,
    schemaNames.filter((n) => n !== "common"),
  );
  for (const dir of exampleDirs) {
    if (list(`examples/${dir}/valid/`).length === 0) {
      throw new Error(`${dir} has no valid example`);
    }
  }
});

for (const dir of exampleDirs) {
  for (const file of list(`examples/${dir}/valid/`)) {
    Deno.test(`valid: ${dir}/${file}`, () => {
      const validate = validator(dir);
      if (!validate(readJson(`examples/${dir}/valid/${file}`))) {
        throw new Error(JSON.stringify(validate.errors, null, 2));
      }
    });
  }
  for (const file of list(`examples/${dir}/invalid/`)) {
    const key = `${dir}/invalid/${file}`;
    Deno.test(`invalid: ${key}`, () => {
      const want = expected[key];
      if (!want) {
        throw new Error(`no entry for ${key} in examples/expected-errors.json`);
      }
      const validate = validator(dir);
      if (validate(readJson(`examples/${key}`))) {
        throw new Error("passed, but must fail");
      }
      const errors = validate.errors ?? [];
      if (
        !errors.some((e: ErrorObject) =>
          e.instancePath === want.instancePath && e.keyword === want.keyword
        )
      ) {
        throw new Error(
          `failed, but not with ${JSON.stringify(want)}:\n${
            JSON.stringify(errors, null, 2)
          }`,
        );
      }
    });
  }
}

Deno.test("expected-errors.json names only invalid examples that exist", () => {
  const files = exampleDirs.flatMap((d) =>
    list(`examples/${d}/invalid/`).map((f) => `${d}/invalid/${f}`)
  );
  sameSet("expected-errors.json keys", Object.keys(expected), files);
});

// --- Column map ---

const columns = readJson("columns.json");
const tables = Object.keys(columns.tables);
const pullSchema: Record<string, string> = {
  poker_sessions: "pull-poker-sessions",
  hands: "pull-hands",
  user_settings: "pull-user-settings",
};

Deno.test("columns.json tables are the push allowlist", () => {
  sameSet(
    "tables",
    tables,
    schemas["push-request"].$defs.change.properties.table.enum,
  );
  sameSet("tables with a pull schema", tables, Object.keys(pullSchema));
});

for (const table of tables) {
  const t = columns.tables[table];
  Deno.test(`columns.json ${table} matches the schema`, () => {
    const props = Object.keys(
      schemas.common.$defs[`${table}_columns`].properties,
    );
    sameSet(
      `${table} client columns in common.schema.json`,
      props,
      t.client_columns,
    );
    for (const c of t.create_only) {
      if (!t.client_columns.includes(c)) {
        throw new Error(`create-only ${c} is not a client column`);
      }
    }
    sameSet(
      "sync columns in common.schema.json",
      Object.keys(schemas.common.$defs.sync_columns.properties),
      columns.sync_columns,
    );
    const keys = t.key.filter((k: string) => !columns.sync_columns.includes(k));
    sameSet(
      `${table} pulled row required columns`,
      schemas[pullSchema[table]].$defs.row.required,
      [...keys, ...t.client_columns, ...columns.sync_columns],
    );
    const fromSwift = Object.values(t.swift.map) as string[];
    sameSet(
      `${table} Swift map minus key and sync columns`,
      fromSwift.filter((c) =>
        !t.key.includes(c) && !columns.sync_columns.includes(c)
      ),
      t.client_columns,
    );
  });
}

Deno.test("hands create-only columns match the hand_number rule in the push schema", () => {
  sameSet(
    "create_only",
    columns.tables.hands.create_only,
    schemas["push-request"].$defs.hands_fields.if.required,
  );
});

// --- Against the design doc ---

const doc = Deno.readTextFileSync(
  new URL("../../../docs/design/1.1-sync.md", here),
);
const section = (start: string, end: string): string => {
  const a = doc.indexOf(start), b = doc.indexOf(end, a);
  if (a < 0 || b < 0) throw new Error(`design doc section not found: ${start}`);
  return doc.slice(a, b);
};
const ticks = (s: string): string[] =>
  [...s.matchAll(/`([^`]+)`/g)].map((m) => m[1]);
// First cell of each table row, skipping the header and the divider.
const firstCells = (s: string): string[] =>
  s.split("\n").filter((l) => l.startsWith("|") && !l.startsWith("|---")).slice(
    1,
  ).map((l) => l.split("|")[1]);

Deno.test("columns.json matches the column lists in design section 2", () => {
  const syncCols = firstCells(
    section("Columns every synced table has", "### 2.1"),
  ).flatMap(ticks);
  sameSet("sync columns", columns.sync_columns, syncCols);
  const docColumns: Record<string, string[]> = {
    poker_sessions: firstCells(section("### 2.4", "### 2.5")).flatMap(ticks),
    hands: firstCells(section("### 2.5", "### 2.6")).flatMap(ticks),
    // 2.6 is prose: "Columns `a`, `b numeric(14,2)`, ...".
    user_settings: ticks(
      section("Primary key `user_id`. Columns", "### 2.7").split("Columns")[1]
        .split(".")[0],
    )
      .map((c) => c.split(" ")[0]),
  };
  for (const table of tables) {
    const t = columns.tables[table];
    const ours = [...new Set([...t.key, ...t.client_columns])].filter((c) =>
      !columns.sync_columns.includes(c)
    );
    const theirs = docColumns[table].filter((c) =>
      !columns.sync_columns.includes(c)
    );
    sameSet(`${table} columns`, ours, theirs);
  }
});

Deno.test("columns.json Swift map matches design section 9.4 exactly", () => {
  const lines = section("| Swift | Column |", "- Dates:").split("\n").filter((
    l,
  ) => l.startsWith("|") && !l.startsWith("|---")).slice(1);
  const docMap: Record<string, Record<string, string>> = {};
  for (const line of lines) {
    const [, swiftCell, columnCell] = line.split("|");
    const swift = ticks(swiftCell);
    // Drop notes in parentheses, which also hold backticked names.
    const cols = ticks(columnCell.replace(/\([^)]*\)/g, ""));
    if (swift.length !== cols.length) {
      throw new Error(
        `9.4 row has ${swift.length} names and ${cols.length} columns: ${line}`,
      );
    }
    const model = swift[0].split(".")[0];
    swift[0] = swift[0].slice(model.length + 1);
    docMap[model] ??= {};
    swift.forEach((s, i) => (docMap[model][s] = cols[i]));
  }
  const ours: Record<string, Record<string, string>> = {};
  for (const table of tables) {
    ours[columns.tables[table].swift.model] = columns.tables[table].swift.map;
  }
  sameSet("models", Object.keys(ours), Object.keys(docMap));
  for (const model of Object.keys(docMap)) {
    const a = JSON.stringify(Object.entries(ours[model]).sort());
    const b = JSON.stringify(Object.entries(docMap[model]).sort());
    if (a !== b) {
      throw new Error(
        `${model} map differs from 9.4:\n  ours ${a}\n  doc  ${b}`,
      );
    }
  }
});
