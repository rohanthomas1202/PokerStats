import { assertEquals } from "jsr:@std/assert@1";
import {
  appleSubject,
  isAppleLinked,
  makeClientSecret,
  readAppleConfig,
} from "./apple.ts";

function b64urlDecode(part: string): Uint8Array<ArrayBuffer> {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - b64.length % 4) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

async function keyPair() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...der))
  }\n-----END PRIVATE KEY-----`;
  return { pem, publicKey: pair.publicKey };
}

const base = {
  teamId: "V2QRL64JUR",
  keyId: "KEY1234567",
  clientId: "com.rohanthomas.PokerStats",
};

Deno.test("client secret has Apple's header and claims and a valid ES256 signature", async () => {
  const { pem, publicKey } = await keyPair();
  const jwt = await makeClientSecret(
    { ...base, privateKey: pem },
    1_700_000_000,
  );
  const [h, c, sig] = jwt.split(".");
  const dec = (p: string) =>
    JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  assertEquals(dec(h), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(dec(c), {
    iss: "V2QRL64JUR",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    aud: "https://appleid.apple.com",
    sub: "com.rohanthomas.PokerStats",
  });
  assertEquals(b64urlDecode(sig).length, 64); // raw r||s, not DER
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    b64urlDecode(sig),
    new TextEncoder().encode(`${h}.${c}`),
  );
  assertEquals(ok, true);
});

Deno.test("private key with escaped \\n newlines is accepted", async () => {
  const { pem } = await keyPair();
  const escaped = pem.replace(/\n/g, "\\n");
  const jwt = await makeClientSecret({ ...base, privateKey: escaped }, 1);
  assertEquals(jwt.split(".").length, 3);
});

Deno.test("readAppleConfig reports missing or blank secret names only", () => {
  const env: Record<string, string> = {
    APPLE_TEAM_ID: "V2QRL64JUR",
    APPLE_KEY_ID: "  ",
    APPLE_PRIVATE_KEY: "pem",
  };
  assertEquals(readAppleConfig((n) => env[n]), {
    ok: false,
    missing: ["APPLE_KEY_ID", "APPLE_CLIENT_ID"],
  });
  const full = { ...env, APPLE_KEY_ID: "K", APPLE_CLIENT_ID: "C" };
  assertEquals(readAppleConfig((n) => full[n as keyof typeof full]), {
    ok: true,
    config: {
      teamId: "V2QRL64JUR",
      keyId: "K",
      clientId: "C",
      privateKey: "pem",
    },
  });
});

Deno.test("isAppleLinked and appleSubject", () => {
  assertEquals(isAppleLinked({ app_metadata: { provider: "apple" } }), true);
  assertEquals(
    isAppleLinked({
      app_metadata: { provider: "email", providers: ["email", "apple"] },
    }),
    true,
  );
  assertEquals(
    isAppleLinked({
      identities: [{ provider: "apple", identity_data: { sub: "s" } }],
    }),
    true,
  );
  assertEquals(isAppleLinked({ app_metadata: { provider: "email" } }), false);
  assertEquals(isAppleLinked({}), false);
  assertEquals(
    appleSubject({
      identities: [{ provider: "apple", identity_data: { sub: "s" } }],
    }),
    "s",
  );
  assertEquals(appleSubject({ identities: null }), undefined);
});
