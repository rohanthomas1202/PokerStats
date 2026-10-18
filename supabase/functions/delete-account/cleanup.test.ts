import { assertEquals } from "jsr:@std/assert@1";
import { type CleanupClient, deleteUserData } from "./cleanup.ts";

const USER = "user-1";

// In-memory stand-in for the parts of supabase-js that cleanup uses.
function fakeClient(
  fileCount: number,
  fail: Partial<Record<string, string>> = {},
) {
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
          const data = files.slice(offset, offset + limit).map((name) => ({
            name,
          }));
          return Promise.resolve({ data, error: null });
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

Deno.test("removes every file when there are more than one page", async () => {
  const fake = fakeClient(250);
  const result = await deleteUserData(fake.client, USER, 100);
  assertEquals(result, { ok: true, filesRemoved: 250 });
  assertEquals(fake.remaining(), 0);
  assertEquals(fake.calls, [
    `list ${USER}/ 0`,
    `list ${USER}/ 100`,
    `list ${USER}/ 200`,
    "remove 100",
    "remove 100",
    "remove 50",
    "delete backup_metadata",
    "delete profiles",
  ]);
});

Deno.test("exact multiple of page size stops on the empty page", async () => {
  const fake = fakeClient(200);
  const result = await deleteUserData(fake.client, USER, 100);
  assertEquals(result, { ok: true, filesRemoved: 200 });
  assertEquals(fake.remaining(), 0);
});

Deno.test("no files still deletes rows", async () => {
  const fake = fakeClient(0);
  assertEquals(await deleteUserData(fake.client, USER), {
    ok: true,
    filesRemoved: 0,
  });
  assertEquals(fake.calls, [
    `list ${USER}/ 0`,
    "delete backup_metadata",
    "delete profiles",
  ]);
});

Deno.test("list error stops before anything is deleted", async () => {
  const fake = fakeClient(5, { list: "boom" });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "list backup files",
    message: "boom",
  });
  assertEquals(fake.calls, [`list ${USER}/ 0`]);
});

Deno.test("remove error stops before row deletes", async () => {
  const fake = fakeClient(5, { remove: "storage down" });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "remove backup files",
    message: "storage down",
  });
  assertEquals(fake.calls.includes("delete backup_metadata"), false);
});

Deno.test("backup_metadata error stops before profile delete", async () => {
  const fake = fakeClient(1, { backup_metadata: "rls" });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "delete backup_metadata",
    message: "rls",
  });
  assertEquals(fake.calls.includes("delete profiles"), false);
});

Deno.test("profile error is returned", async () => {
  const fake = fakeClient(1, { profiles: "fk" });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, { ok: false, step: "delete profile", message: "fk" });
});
