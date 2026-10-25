// Sign in with Apple token revocation (App Review 5.1.1(v)).
//
// Flow, per Apple's REST API docs:
// 1. Build a client_secret JWT (ES256, signed with the .p8 key):
//    header { alg: "ES256", kid: <Key ID> },
//    claims { iss: <Team ID>, iat, exp, aud: "https://appleid.apple.com",
//             sub: <client ID> }.
// 2. POST the app's fresh authorization code to /auth/token
//    (grant_type=authorization_code) to get a refresh token.
// 3. POST that token to /auth/revoke.
// Nothing here logs or returns secrets, codes, or tokens.

export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
// Issuer of Apple's id_tokens and audience of our client secret.
const APPLE_ISSUER = "https://appleid.apple.com";
// Apple allows up to six months; the secret is only used for two calls.
const CLIENT_SECRET_TTL_SECONDS = 300;

// Supabase Edge Function secret names.
export const APPLE_ENV = {
  teamId: "APPLE_TEAM_ID",
  keyId: "APPLE_KEY_ID",
  clientId: "APPLE_CLIENT_ID",
  privateKey: "APPLE_PRIVATE_KEY",
} as const;

export type AppleConfig = Record<keyof typeof APPLE_ENV, string>;

export type ReadConfigResult =
  | { ok: true; config: AppleConfig }
  | { ok: false; missing: string[] };

// Reads the four secrets. Reports only the names of missing ones.
export function readAppleConfig(
  getEnv: (name: string) => string | undefined,
): ReadConfigResult {
  const missing: string[] = [];
  const config = {} as AppleConfig;
  for (const [field, name] of Object.entries(APPLE_ENV)) {
    const value = getEnv(name)?.trim();
    if (!value) missing.push(name);
    else config[field as keyof AppleConfig] = value;
  }
  return missing.length ? { ok: false, missing } : { ok: true, config };
}

// Supabase user fields used to decide whether the account is Apple-linked.
export type AppleLinkInfo = {
  app_metadata?: { provider?: string; providers?: string[] };
  identities?: {
    provider: string;
    identity_data?: { sub?: string } | null;
  }[] | null;
};

export function isAppleLinked(user: AppleLinkInfo): boolean {
  return user.app_metadata?.provider === "apple" ||
    (user.app_metadata?.providers ?? []).includes("apple") ||
    (user.identities ?? []).some((i) => i.provider === "apple");
}

// The Apple user ID ("sub") Supabase stored for this account, if any.
export function appleSubject(user: AppleLinkInfo): string | undefined {
  return (user.identities ?? []).find((i) => i.provider === "apple")
    ?.identity_data?.sub ?? undefined;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function base64urlJSON(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

// Accepts the .p8 contents with real newlines or "\n" escapes.
async function importP8(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

// WebCrypto's ECDSA output is raw r||s (IEEE P1363), which is the JWS format.
export async function makeClientSecret(
  config: AppleConfig,
  nowSeconds: number,
): Promise<string> {
  const header = { alg: "ES256", kid: config.keyId };
  const claims = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + CLIENT_SECRET_TTL_SECONDS,
    aud: APPLE_ISSUER,
    sub: config.clientId,
  };
  const signingInput = `${base64urlJSON(header)}.${base64urlJSON(claims)}`;
  const key = await importP8(config.privateKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

type IdTokenClaims = { iss?: unknown; aud?: unknown; sub?: unknown };

// Does not verify the signature or exp. Safe only for the id_token returned
// directly by Apple's token endpoint over TLS; do not reuse for a
// client-supplied token.
function decodeUnverifiedJwtClaims(jwt: string): IdTokenClaims | undefined {
  try {
    const part = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = part + "=".repeat((4 - part.length % 4) % 4);
    const claims = JSON.parse(atob(padded));
    return typeof claims === "object" && claims !== null &&
        !Array.isArray(claims)
      ? claims
      : undefined;
  } catch {
    return undefined;
  }
}

function hasAudience(aud: unknown, clientId: string): boolean {
  return aud === clientId || (Array.isArray(aud) && aud.includes(clientId));
}

// Apple error bodies are {"error": "..."}; only that code is reported.
async function appleError(res: Response): Promise<string> {
  try {
    const body = await res.json();
    if (typeof body?.error === "string") return `${res.status} ${body.error}`;
  } catch {
    // fall through
  }
  return `${res.status}`;
}

// The handler turns these into its response codes.
export type RevokeFailureCode =
  | "server_not_configured"
  | "apple_token_invalid"
  | "apple_account_mismatch"
  | "delete_failed";

export type RevokeResult =
  | { ok: true }
  | { ok: false; code: RevokeFailureCode; message: string };

export interface RevokeOptions {
  config: AppleConfig;
  authorizationCode: string;
  // The exchanged token must belong to this Apple user (Supabase's stored sub).
  expectedSubject: string;
  fetch: typeof fetch;
  nowSeconds: number;
}

export async function revokeAppleToken(
  opts: RevokeOptions,
): Promise<RevokeResult> {
  try {
    return await exchangeAndRevoke(opts);
  } catch (err) {
    // fetch rejects on network failure; report the error type only.
    const name = err instanceof Error ? err.name : "error";
    return {
      ok: false,
      code: "delete_failed",
      message: `request failed (${name})`,
    };
  }
}

async function exchangeAndRevoke(opts: RevokeOptions): Promise<RevokeResult> {
  let clientSecret: string;
  try {
    clientSecret = await makeClientSecret(opts.config, opts.nowSeconds);
  } catch (err) {
    const name = err instanceof Error ? err.name : "error";
    return {
      ok: false,
      code: "server_not_configured",
      message: `client secret: invalid private key (${name})`,
    };
  }
  const form = (fields: Record<string, string>) =>
    new URLSearchParams({
      client_id: opts.config.clientId,
      client_secret: clientSecret,
      ...fields,
    });

  const tokenRes = await opts.fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form({
      grant_type: "authorization_code",
      code: opts.authorizationCode,
    }),
  });
  if (!tokenRes.ok) {
    return {
      ok: false,
      code: "delete_failed",
      message: `token exchange: ${await appleError(tokenRes)}`,
    };
  }
  const tokens = await tokenRes.json();

  const claims = typeof tokens.id_token === "string"
    ? decodeUnverifiedJwtClaims(tokens.id_token)
    : undefined;
  if (!claims) {
    return {
      ok: false,
      code: "delete_failed",
      message: "token exchange: no readable id_token",
    };
  }
  if (
    claims.iss !== APPLE_ISSUER ||
    !hasAudience(claims.aud, opts.config.clientId)
  ) {
    return {
      ok: false,
      code: "apple_token_invalid",
      message: "token exchange: id_token iss or aud is wrong",
    };
  }
  if (!opts.expectedSubject || claims.sub !== opts.expectedSubject) {
    return {
      ok: false,
      code: "apple_account_mismatch",
      message: "token exchange: Apple account does not match this user",
    };
  }

  const [token, hint] = typeof tokens.refresh_token === "string"
    ? [tokens.refresh_token, "refresh_token"]
    : typeof tokens.access_token === "string"
    ? [tokens.access_token, "access_token"]
    : [undefined, undefined];
  if (!token || !hint) {
    return {
      ok: false,
      code: "delete_failed",
      message: "token exchange: no token in response",
    };
  }

  const revokeRes = await opts.fetch(APPLE_REVOKE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form({ token, token_type_hint: hint }),
  });
  if (!revokeRes.ok) {
    return {
      ok: false,
      code: "delete_failed",
      message: `revoke: ${await appleError(revokeRes)}`,
    };
  }
  return { ok: true };
}
