// Rewrites the expected values in datasets/*.json and display.json from
// reference.ts. Run after changing a dataset's inputs, then review the diff:
//   deno run --allow-read=. --allow-write=. update.ts
import { display, expectedFor } from "./reference.ts";

const write = (path: string, value: unknown) =>
  Deno.writeTextFileSync(path, JSON.stringify(value, null, 2) + "\n");
for (const e of Deno.readDirSync("datasets")) {
  const d = JSON.parse(Deno.readTextFileSync(`datasets/${e.name}`));
  write(`datasets/${e.name}`, { ...d, expected: expectedFor(d) });
}
const shown = JSON.parse(Deno.readTextFileSync("display.json"));
shown.cases = shown.cases.map((
  c: { format: string; value: number | null },
) => ({ ...c, expected: display(c.format, c.value) }));
write("display.json", shown);
