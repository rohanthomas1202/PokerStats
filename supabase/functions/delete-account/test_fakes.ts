// Test-only in-memory fakes for the Supabase client.
import type { CleanupClient } from "./cleanup.ts";

export const USER = "user-1";

type FakeOptions = {
  fail?: Partial<Record<string, string>>;
  // Extra files as paths relative to {USER}/, e.g. "a/b/c.json.gz".
  nested?: string[];
  // Paths (relative to {USER}/) that remove() reports as removed but keeps,
  // like a backup uploaded again mid-deletion.
  sticky?: string[];
  shortPageAt?: number; // offset of the {USER}/ page that comes back halved
};

// In-memory stand-in for the parts of supabase-js that cleanup uses. Storage
// is a flat set of full object paths; list() returns the direct children of
// a prefix, files with an id and sub-folders with id null, sorted by name.
export function fakeClient(fileCount: number, opts: FakeOptions = {}) {
  const fail = opts.fail ?? {};
  const root = `${USER}/`;
  let objects = [
    ...Array.from({ length: fileCount }, (_, i) => `${root}f${i}.json.gz`),
    ...(opts.nested ?? []).map((p) => `${root}${p}`),
  ];
  const sticky = new Set((opts.sticky ?? []).map((p) => `${root}${p}`));
  const calls: string[] = [];
  const err = (key: string) => (fail[key] ? { message: fail[key]! } : null);

  const client: CleanupClient = {
    storage: {
      from: () => ({
        list: (prefix, { limit, offset }) => {
          calls.push(`list ${prefix} ${offset}`);
          if (fail.list) {
            return Promise.resolve({ data: null, error: err("list") });
          }
          const children = new Map<string, string | null>();
          for (const path of objects) {
            if (!path.startsWith(prefix)) continue;
            const rest = path.slice(prefix.length);
            const slash = rest.indexOf("/");
            if (slash === -1) children.set(rest, `id-${path}`);
            else children.set(rest.slice(0, slash), null);
          }
          const entries = [...children.entries()]
            .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
            .map(([name, id]) => ({ name, id }));
          let page = entries.slice(offset, offset + limit);
          if (prefix === root && offset === opts.shortPageAt) {
            page = page.slice(0, limit / 2);
          }
          return Promise.resolve({ data: page, error: null });
        },
        remove: (paths) => {
          calls.push(`remove ${paths.length}`);
          if (fail.remove) return Promise.resolve({ error: err("remove") });
          const gone = new Set(paths.filter((p) => !sticky.has(p)));
          objects = objects.filter((p) => !gone.has(p));
          return Promise.resolve({ error: null });
        },
      }),
    },
    from: (table) => ({
      delete: () => ({
        eq: () => {
          calls.push(`delete ${table}`);
          return Promise.resolve({ error: err(table) });
        },
      }),
    }),
  };
  return {
    client,
    calls,
    remaining: () => objects.length,
    remainingPaths: () => [...objects],
  };
}
