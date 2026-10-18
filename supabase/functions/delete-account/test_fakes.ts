// Test-only in-memory fakes for the Supabase client.
import type { CleanupClient } from "./cleanup.ts";

export const USER = "user-1";

type FakeOptions = {
  fail?: Partial<Record<string, string>>;
  folders?: string[]; // entries returned with id: null
  shortPageAt?: number; // offset whose page comes back truncated by half
};

// In-memory stand-in for the parts of supabase-js that cleanup uses.
export function fakeClient(fileCount: number, opts: FakeOptions = {}) {
  const fail = opts.fail ?? {};
  let files = Array.from({ length: fileCount }, (_, i) => `f${i}.json.gz`);
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
          const entries = [
            ...(opts.folders ?? []).map((name) => ({ name, id: null })),
            ...files.map((name) => ({ name, id: `id-${name}` })),
          ];
          let page = entries.slice(offset, offset + limit);
          if (offset === opts.shortPageAt) page = page.slice(0, limit / 2);
          return Promise.resolve({ data: page, error: null });
        },
        remove: (paths) => {
          calls.push(`remove ${paths.length}`);
          if (fail.remove) return Promise.resolve({ error: err("remove") });
          files = files.filter((f) => !paths.includes(`${USER}/${f}`));
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
  return { client, calls, remaining: () => files.length };
}
