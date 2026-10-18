import { assertEquals } from "jsr:@std/assert@1";
import { deleteUserData, MAX_DEPTH, REMOVE_BATCH } from "./cleanup.ts";
import { fakeClient, USER } from "./test_fakes.ts";

Deno.test("removes every file when there are more than one page", async () => {
  const fake = fakeClient(250);
  const result = await deleteUserData(fake.client, USER, 100);
  assertEquals(result, { ok: true, filesRemoved: 250 });
  assertEquals(fake.remaining(), 0);
  assertEquals(fake.calls, [
    `list ${USER}/ 0`,
    `list ${USER}/ 100`,
    `list ${USER}/ 200`,
    "remove 250",
    `list ${USER}/ 0`,
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

Deno.test("remove batches are REMOVE_BATCH regardless of page size", async () => {
  const fake = fakeClient(2500);
  const result = await deleteUserData(fake.client, USER, 100);
  assertEquals(result, { ok: true, filesRemoved: 2500 });
  assertEquals(REMOVE_BATCH, 1000);
  assertEquals(fake.calls.filter((c) => c.startsWith("remove")), [
    "remove 1000",
    "remove 1000",
    "remove 500",
  ]);
});

Deno.test("no files still deletes rows", async () => {
  const fake = fakeClient(0);
  assertEquals(await deleteUserData(fake.client, USER), {
    ok: true,
    filesRemoved: 0,
  });
  assertEquals(fake.calls, [
    `list ${USER}/ 0`,
    `list ${USER}/ 0`,
    "delete backup_metadata",
    "delete profiles",
  ]);
});

Deno.test("list error stops before anything is deleted", async () => {
  const fake = fakeClient(5, { fail: { list: "boom" } });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "list backup files",
    message: "boom",
  });
  assertEquals(fake.calls, [`list ${USER}/ 0`]);
});

Deno.test("files in nested folders are deleted", async () => {
  const fake = fakeClient(2, { nested: ["old/a.json.gz", "old/b.json.gz"] });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, { ok: true, filesRemoved: 4 });
  assertEquals(fake.remaining(), 0);
  assertEquals(fake.calls, [
    `list ${USER}/ 0`,
    `list ${USER}/old/ 0`,
    "remove 4",
    `list ${USER}/ 0`,
    "delete backup_metadata",
    "delete profiles",
  ]);
});

Deno.test("deep nesting is followed and paged at each level", async () => {
  const deep = Array.from({ length: 150 }, (_, i) => `a/b/c/d/f${i}.json.gz`);
  const fake = fakeClient(120, { nested: [...deep, "a/x.json.gz"] });
  const result = await deleteUserData(fake.client, USER, 100);
  assertEquals(result, { ok: true, filesRemoved: 271 });
  assertEquals(fake.remaining(), 0);
  const listing = fake.calls.slice(0, fake.calls.indexOf("remove 271"));
  assertEquals(listing, [
    `list ${USER}/ 0`,
    `list ${USER}/ 100`, // root has 121 entries: 120 files + folder "a"
    `list ${USER}/a/ 0`,
    `list ${USER}/a/b/ 0`,
    `list ${USER}/a/b/c/ 0`,
    `list ${USER}/a/b/c/d/ 0`,
    `list ${USER}/a/b/c/d/ 100`,
  ]);
});

Deno.test("nesting deeper than MAX_DEPTH fails the list step", async () => {
  const path = Array.from({ length: MAX_DEPTH + 1 }, (_, i) => `d${i}`).join(
    "/",
  );
  const fake = fakeClient(1, { nested: [`${path}/f.json.gz`] });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result.ok, false);
  assertEquals(result.ok === false && result.step, "list backup files");
  assertEquals(fake.calls.some((c) => c.startsWith("remove")), false);
});

Deno.test("leftover in a nested folder fails verification", async () => {
  const fake = fakeClient(3, {
    nested: ["a/b/keep.json.gz", "a/b/gone.json.gz"],
    sticky: ["a/b/keep.json.gz"],
  });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "verify backup files removed",
    message: `1+ files still under ${USER}/`,
  });
  assertEquals(fake.remainingPaths(), [`${USER}/a/b/keep.json.gz`]);
  assertEquals(fake.calls.includes("delete backup_metadata"), false);
});

Deno.test("list error inside a nested folder stops before removing", async () => {
  const fake = fakeClient(0, { nested: ["a/f.json.gz"] });
  // Fail every list after the root listing.
  const list = fake.client.storage.from("backups").list;
  const bucket = fake.client.storage.from("backups");
  let n = 0;
  fake.client.storage.from = () => ({
    ...bucket,
    list: (prefix, o) =>
      n++ === 0
        ? list(prefix, o)
        : Promise.resolve({ data: null, error: { message: "nested boom" } }),
  });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "list backup files",
    message: "nested boom",
  });
  assertEquals(fake.remaining(), 1);
});

Deno.test("short page before the real end fails verification", async () => {
  const fake = fakeClient(250, { shortPageAt: 100 });
  const result = await deleteUserData(fake.client, USER, 100);
  assertEquals(result, {
    ok: false,
    step: "verify backup files removed",
    message: `100+ files still under ${USER}/`,
  });
  assertEquals(fake.remaining(), 100);
  assertEquals(fake.calls.includes("delete backup_metadata"), false);
});

Deno.test("remove error stops before row deletes", async () => {
  const fake = fakeClient(5, { fail: { remove: "storage down" } });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "remove backup files",
    message: "storage down",
  });
  assertEquals(fake.calls.includes("delete backup_metadata"), false);
});

Deno.test("backup_metadata error stops before profile delete", async () => {
  const fake = fakeClient(1, { fail: { backup_metadata: "rls" } });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "delete backup_metadata",
    message: "rls",
  });
  assertEquals(fake.calls.includes("delete profiles"), false);
});

Deno.test("profile error is returned", async () => {
  const fake = fakeClient(1, { fail: { profiles: "fk" } });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, { ok: false, step: "delete profile", message: "fk" });
});
