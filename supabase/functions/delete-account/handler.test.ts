import { assertEquals } from "jsr:@std/assert@1";
import { type AdminClient, makeHandler, type UserClient } from "./handler.ts";
import { fakeClient, USER } from "./test_fakes.ts";

type Setup = {
  cleanupFail?: Partial<Record<string, string>>;
  deleteUserError?: string;
  getUserError?: string;
  throwOnAdmin?: boolean;
};

function setup(opts: Setup = {}) {
  const fake = fakeClient(3, { fail: opts.cleanupFail });
  const deletedUsers: string[] = [];
  const admin: AdminClient = {
    ...fake.client,
    auth: {
      admin: {
        deleteUser: (id) => {
          deletedUsers.push(id);
          const error = opts.deleteUserError
            ? { message: opts.deleteUserError }
            : null;
          return Promise.resolve({ error });
        },
      },
    },
  };
  const user: UserClient = {
    auth: {
      getUser: () =>
        Promise.resolve(
          opts.getUserError
            ? {
              data: { user: null },
              error: { message: opts.getUserError },
            }
            : { data: { user: { id: USER } }, error: null },
        ),
    },
  };
  const handler = makeHandler({
    createAdminClient: () => {
      if (opts.throwOnAdmin) throw new Error("secret detail");
      return admin;
    },
    createUserClient: () => user,
  });
  return { handler, deletedUsers, fake };
}

const post = (
  headers: Record<string, string> = { Authorization: "Bearer t" },
) => new Request("http://x/delete-account", { method: "POST", headers });

async function call(handler: (r: Request) => Promise<Response>, req: Request) {
  const res = await handler(req);
  return { status: res.status, body: await res.json() };
}

// Silence the expected console.error output from failure paths.
function quiet<T>(fn: () => Promise<T>): Promise<T> {
  const orig = console.error;
  console.error = () => {};
  return fn().finally(() => (console.error = orig));
}

Deno.test("405 on non-POST", async () => {
  const { handler, deletedUsers } = setup();
  const req = new Request("http://x/delete-account", { method: "GET" });
  assertEquals(await call(handler, req), {
    status: 405,
    body: { error: "Method not allowed" },
  });
  assertEquals(deletedUsers, []);
});

Deno.test("401 without Authorization header", async () => {
  const { handler, deletedUsers } = setup();
  assertEquals(await call(handler, post({})), {
    status: 401,
    body: { error: "Missing authorization" },
  });
  assertEquals(deletedUsers, []);
});

Deno.test("401 on invalid token", async () => {
  const { handler, deletedUsers, fake } = setup({ getUserError: "bad jwt" });
  assertEquals(await call(handler, post()), {
    status: 401,
    body: { error: "Invalid token" },
  });
  assertEquals(deletedUsers, []);
  assertEquals(fake.calls, []);
});

Deno.test("200 deletes data then the auth user", async () => {
  const { handler, deletedUsers, fake } = setup();
  assertEquals(await call(handler, post()), {
    status: 200,
    body: { message: "Account deleted successfully" },
  });
  assertEquals(deletedUsers, [USER]);
  assertEquals(fake.remaining(), 0);
});

for (
  const [key, step] of [
    ["remove", "remove backup files"],
    ["backup_metadata", "delete backup_metadata"],
    ["profiles", "delete profile"],
  ]
) {
  Deno.test(`cleanup failure (${key}) returns generic 500 and keeps auth user`, async () => {
    const { handler, deletedUsers } = setup({
      cleanupFail: { [key]: "secret detail" },
    });
    assertEquals(await quiet(() => call(handler, post())), {
      status: 500,
      body: { error: "Account deletion failed", step, retryable: true },
    });
    assertEquals(deletedUsers, []);
  });
}

Deno.test("auth user delete failure returns generic 500", async () => {
  const { handler } = setup({ deleteUserError: "secret detail" });
  assertEquals(await quiet(() => call(handler, post())), {
    status: 500,
    body: {
      error: "Account deletion failed",
      step: "delete auth user",
      retryable: true,
    },
  });
});

Deno.test("unexpected error returns generic 500", async () => {
  const { handler, deletedUsers } = setup({ throwOnAdmin: true });
  assertEquals(await quiet(() => call(handler, post())), {
    status: 500,
    body: {
      error: "Account deletion failed",
      step: "unexpected",
      retryable: true,
    },
  });
  assertEquals(deletedUsers, []);
});
