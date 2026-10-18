import { assertEquals } from "jsr:@std/assert@1";
import { deleteUserData, REMOVE_BATCH } from "./cleanup.ts";
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

Deno.test("folder entry (null id) fails the list step", async () => {
  const fake = fakeClient(5, { folders: ["nested"] });
  const result = await deleteUserData(fake.client, USER);
  assertEquals(result, {
    ok: false,
    step: "list backup files",
    message: `unexpected folder ${USER}/nested`,
  });
  assertEquals(fake.calls, [`list ${USER}/ 0`]);
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
