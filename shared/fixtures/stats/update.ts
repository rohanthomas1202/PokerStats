// Rewrites the expected values in datasets/*.json and display.json from
// reference.ts. Run after changing a dataset's inputs, then review the diff.
// Paths resolve from this file, so it works from any folder, for example from
// the repo root:
//   deno run --allow-read=shared/fixtures/stats --allow-write=shared/fixtures/stats shared/fixtures/stats/update.ts
import { display, expectedFor } from "./reference.ts";

const here = new URL("./", import.meta.url);
const read = (path: string) =>
  JSON.parse(Deno.readTextFileSync(new URL(path, here)));
const write = (path: string, value: unknown) =>
  Deno.writeTextFileSync(
    new URL(path, here),
    JSON.stringify(value, null, 2) + "\n",
  );
for (const e of Deno.readDirSync(new URL("datasets/", here))) {
  const d = read(`datasets/${e.name}`);
  write(`datasets/${e.name}`, { ...d, expected: expectedFor(d) });
}
const shown = read("display.json");
shown.cases = shown.cases.map((
  c: { format: string; value: number | null },
) => ({ ...c, expected: display(c.format, c.value) }));
write("display.json", shown);
