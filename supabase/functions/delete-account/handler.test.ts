import { assertEquals } from "jsr:@std/assert@1";
import { type AdminClient, makeHandler, type UserClient } from "./handler.ts";
import { fakeClient, USER } from "./test_fakes.ts";
import type { AppleLinkInfo } from "./apple.ts";

type Setup = {
  cleanupFail?: Partial<Record<string, string>>;
  // Supabase user fields; defaults to a non-Apple (email) user.
  userFields?: AppleLinkInfo;
  env?: Record<string, string>;
  fetch?: typeof fetch;
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
          fake.calls.push("delete auth user");
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
            : {
              data: {
                user: {
                  id: USER,
                  ...(opts.userFields ??
                    { app_metadata: { provider: "email" } }),
                },
              },
              error: null,
            },
        ),
    },
  };
  const handler = makeHandler({
    createAdminClient: () => {
      if (opts.throwOnAdmin) throw new Error("secret detail");
      return admin;
    },
    createUserClient: () => user,
    getEnv: (name) => opts.env?.[name],
    fetch: opts.fetch ?? (() => {
      throw new Error("unexpected fetch");
    }),
    nowSeconds: () => 1_700_000_000,
  });
  return { handler, deletedUsers, fake };
}

const post = (
  headers: Record<string, string> = { Authorization: "Bearer t" },
  body?: unknown,
) =>
  new Request("http://x/delete-account", {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

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

// MARK: - Apple token revocation

const APPLE_SUB = "001234.abcdef.1234";
const CODE = "c-fresh-auth-code-SECRET";
const REFRESH = "r-refresh-token-SECRET";

async function testP8(): Promise<string> {
  const { privateKey } = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", privateKey),
  );
  const b64 = btoa(String.fromCharCode(...der));
  return `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----`;
}

async function appleEnv(): Promise<Record<string, string>> {
  return {
    APPLE_TEAM_ID: "V2QRL64JUR",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_CLIENT_ID: "com.rohanthomas.PokerStats",
    APPLE_PRIVATE_KEY: await testP8(),
  };
}

const appleUser: AppleLinkInfo = {
  app_metadata: { provider: "apple", providers: ["apple"] },
  identities: [{ provider: "apple", identity_data: { sub: APPLE_SUB } }],
};

const fakeIdToken = (sub: string) =>
  `h.${btoa(JSON.stringify({ sub })).replace(/=+$/, "")}.s`;

type AppleReply = { status: number; body?: unknown };

// Fake Apple endpoints. Logs "apple token"/"apple revoke" into the shared
// call log so ordering against storage/DB/auth deletes can be asserted.
function fakeApple(
  log: { calls: string[] },
  replies: { token?: AppleReply; revoke?: AppleReply } = {},
) {
  const requests: { url: string; form: Record<string, string> }[] = [];
  const fetchFn =
    (async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      const form = Object.fromEntries(new URLSearchParams(String(init?.body)));
      requests.push({ url, form });
      if (url.endsWith("/auth/token")) {
        log.calls.push("apple token");
        const r = replies.token ??
          {
            status: 200,
            body: {
              access_token: "a-access-SECRET",
              refresh_token: REFRESH,
              id_token: fakeIdToken(APPLE_SUB),
            },
          };
        return new Response(JSON.stringify(r.body ?? {}), { status: r.status });
      }
      log.calls.push("apple revoke");
      const r = replies.revoke ?? { status: 200 };
      return new Response(r.body ? JSON.stringify(r.body) : null, {
        status: r.status,
      });
    }) as typeof fetch;
  return { fetchFn, requests };
}

// Runs fn with console.error captured.
async function captureErrors<T>(fn: () => Promise<T>) {
  const orig = console.error;
  const lines: string[] = [];
  console.error = (...args: unknown[]) =>
    lines.push(args.map(String).join(" "));
  try {
    return { result: await fn(), logs: lines.join("\n") };
  } finally {
    console.error = orig;
  }
}

function assertNoSecrets(text: string, env: Record<string, string>) {
  const keyBody = env.APPLE_PRIVATE_KEY.split("\n")[1];
  for (const secret of [CODE, REFRESH, "a-access-SECRET", keyBody]) {
    assertEquals(text.includes(secret), false, "secret leaked");
  }
}

Deno.test("apple: revokes before any data is deleted, then deletes everything", async () => {
  const env = await appleEnv();
  const log = { calls: [] as string[] };
  const apple = fakeApple(log);
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  log.calls = fake.calls; // one shared log for Apple, storage, DB and auth

  assertEquals(
    await call(handler, post(undefined, { authorization_code: CODE })),
    { status: 200, body: { message: "Account deleted successfully" } },
  );
  assertEquals(fake.calls, [
    "apple token",
    "apple revoke",
    `list ${USER}/ 0`,
    "remove 3",
    `list ${USER}/ 0`,
    "delete backup_metadata",
    "delete profiles",
    "delete auth user",
  ]);
  assertEquals(deletedUsers, [USER]);

  const [token, revoke] = apple.requests;
  assertEquals(token.url, "https://appleid.apple.com/auth/token");
  assertEquals(token.form.grant_type, "authorization_code");
  assertEquals(token.form.code, CODE);
  assertEquals(token.form.client_id, "com.rohanthomas.PokerStats");
  assertEquals(token.form.client_secret.split(".").length, 3);
  assertEquals(revoke.url, "https://appleid.apple.com/auth/revoke");
  assertEquals(revoke.form.token, REFRESH);
  assertEquals(revoke.form.token_type_hint, "refresh_token");
  assertEquals(revoke.form.client_id, "com.rohanthomas.PokerStats");
  assertEquals(revoke.form.client_secret, token.form.client_secret);
});

Deno.test("apple: revoke error returns generic 500 and deletes nothing", async () => {
  const env = await appleEnv();
  const apple = fakeApple({ calls: [] }, {
    revoke: { status: 400, body: { error: "invalid_client" } },
  });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  const { result, logs } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result, {
    status: 500,
    body: {
      error: "Account deletion failed",
      step: "revoke apple token",
      retryable: true,
    },
  });
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
  assertEquals(fake.remaining(), 3);
  assertEquals(logs.includes("revoke: 400 invalid_client"), true);
  assertNoSecrets(logs, env);
});

Deno.test("apple: token exchange error (expired code) deletes nothing", async () => {
  const env = await appleEnv();
  const apple = fakeApple({ calls: [] }, {
    token: { status: 400, body: { error: "invalid_grant" } },
  });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  const { result, logs } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result.status, 500);
  assertEquals(result.body.step, "revoke apple token");
  assertEquals(apple.requests.length, 1); // never reached /auth/revoke
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
  assertEquals(logs.includes("token exchange: 400 invalid_grant"), true);
  assertNoSecrets(logs, env);
});

Deno.test("apple: network failure deletes nothing", async () => {
  const env = await appleEnv();
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: (() => Promise.reject(new TypeError("dns"))) as typeof fetch,
  });
  const { result } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result.status, 500);
  assertEquals(result.body.step, "revoke apple token");
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
});

Deno.test("apple: code for a different Apple account is rejected", async () => {
  const env = await appleEnv();
  const apple = fakeApple({ calls: [] }, {
    token: {
      status: 200,
      body: { refresh_token: REFRESH, id_token: fakeIdToken("someone-else") },
    },
  });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  const { result } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result.status, 500);
  assertEquals(apple.requests.length, 1); // no revoke
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
});

Deno.test("apple: missing secrets returns generic 500, logs names only, deletes nothing", async () => {
  const env = await appleEnv();
  const partial = {
    APPLE_TEAM_ID: env.APPLE_TEAM_ID,
    APPLE_PRIVATE_KEY: env.APPLE_PRIVATE_KEY,
  };
  const apple = fakeApple({ calls: [] });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env: partial,
    fetch: apple.fetchFn,
  });
  const { result, logs } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result, {
    status: 500,
    body: {
      error: "Account deletion failed",
      step: "revoke apple token",
      retryable: true,
    },
  });
  assertEquals(apple.requests, []);
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
  assertEquals(logs.includes("APPLE_KEY_ID, APPLE_CLIENT_ID"), true);
  assertNoSecrets(logs, env);
});

Deno.test("apple: malformed private key returns generic 500 and deletes nothing", async () => {
  const env = { ...(await appleEnv()), APPLE_PRIVATE_KEY: "not-a-key" };
  const apple = fakeApple({ calls: [] });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  const { result, logs } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result.status, 500);
  assertEquals(apple.requests, []);
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
  assertEquals(logs.includes("not-a-key"), false);
});

Deno.test("apple: missing authorization_code returns 400 and deletes nothing", async () => {
  const env = await appleEnv();
  const apple = fakeApple({ calls: [] });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  const { result } = await captureErrors(() => call(handler, post()));
  assertEquals(result, {
    status: 400,
    body: {
      error: "Apple re-authentication required",
      code: "apple_reauth_required",
      step: "revoke apple token",
      retryable: true,
    },
  });
  assertEquals(apple.requests, []);
  assertEquals(fake.calls.length, 0);
  assertEquals(deletedUsers, []);
});

Deno.test("apple: Apple-linked user with no stored Apple sub fails closed", async () => {
  const env = await appleEnv();
  const apple = fakeApple({ calls: [] });
  const { handler, deletedUsers, fake } = setup({
    userFields: { app_metadata: { provider: "apple" }, identities: [] },
    env,
    fetch: apple.fetchFn,
  });
  const { result, logs } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result.status, 500);
  assertEquals(result.body.step, "revoke apple token");
  assertEquals(apple.requests, []);
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
  assertEquals(logs.includes("no Apple identity sub"), true);
});

Deno.test("apple: token response without id_token is rejected", async () => {
  const env = await appleEnv();
  const apple = fakeApple({ calls: [] }, {
    token: { status: 200, body: { refresh_token: REFRESH } },
  });
  const { handler, deletedUsers, fake } = setup({
    userFields: appleUser,
    env,
    fetch: apple.fetchFn,
  });
  const { result } = await captureErrors(() =>
    call(handler, post(undefined, { authorization_code: CODE }))
  );
  assertEquals(result.status, 500);
  assertEquals(apple.requests.length, 1); // no revoke
  assertEquals(fake.calls, []);
  assertEquals(deletedUsers, []);
});

Deno.test("non-Apple user skips revocation even without secrets", async () => {
  const { handler, deletedUsers } = setup({
    userFields: {
      app_metadata: { provider: "email", providers: ["email"] },
      identities: [{ provider: "email", identity_data: { sub: USER } }],
    },
    env: {},
  });
  // setup's default fetch throws, so any Apple call would fail this test.
  assertEquals(await call(handler, post()), {
    status: 200,
    body: { message: "Account deleted successfully" },
  });
  assertEquals(deletedUsers, [USER]);
});
