// Request handler for delete-account, with the Supabase clients injected so
// the HTTP contract can be tested without a live project.
import {
  type AppleLinkInfo,
  appleSubject,
  isAppleLinked,
  readAppleConfig,
  revokeAppleToken,
} from "./apple.ts";
import { type CleanupClient, deleteUserData } from "./cleanup.ts";

type AuthError = { message: string } | null;

export interface AdminClient extends CleanupClient {
  auth: {
    admin: { deleteUser(id: string): PromiseLike<{ error: AuthError }> };
  };
}

export interface UserClient {
  auth: {
    getUser(): PromiseLike<{
      data: { user: ({ id: string } & AppleLinkInfo) | null };
      error: AuthError;
    }>;
  };
}

export interface HandlerDeps {
  createAdminClient(): AdminClient;
  createUserClient(authHeader: string): UserClient;
  // Used for the Apple secrets (APPLE_TEAM_ID etc.).
  getEnv(name: string): string | undefined;
  fetch: typeof fetch;
  nowSeconds?: () => number;
}

// Optional JSON body: { "authorization_code": "<fresh Apple code>" }.
async function readAuthorizationCode(
  req: Request,
): Promise<string | undefined> {
  try {
    const body = await req.json();
    const code = body?.authorization_code;
    return typeof code === "string" && code.length > 0 ? code : undefined;
  } catch {
    return undefined; // empty or non-JSON body
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Details go to the log only; the client gets a generic body.
function failure(step: string): Response {
  return json({ error: "Account deletion failed", step, retryable: true }, 500);
}

export function makeHandler(deps: HandlerDeps) {
  return async (req: Request): Promise<Response> => {
    // Only allow POST
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    // Extract user from JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing authorization" }, 401);
    }

    try {
      // Create admin client for privileged operations
      const supabaseAdmin = deps.createAdminClient();

      // Create user client to identify the caller
      const supabaseUser = deps.createUserClient(authHeader);

      const {
        data: { user },
        error: userError,
      } = await supabaseUser.auth.getUser();

      if (userError || !user) {
        return json({ error: "Invalid token" }, 401);
      }

      const userId = user.id;

      // 0. Apple-linked accounts: revoke the Sign in with Apple token first,
      // so a failure here leaves all data and the account in place.
      if (isAppleLinked(user)) {
        const code = await readAuthorizationCode(req);
        if (!code) {
          console.error(
            `delete-account: Apple-linked user ${userId} sent no authorization_code`,
          );
          return json({
            error: "Apple re-authentication required",
            step: "revoke apple token",
            retryable: true,
          }, 400);
        }
        const config = readAppleConfig(deps.getEnv);
        if (!config.ok) {
          console.error(
            `delete-account: Apple revocation not configured, missing secrets: ${
              config.missing.join(", ")
            }`,
          );
          return failure("revoke apple token");
        }
        const revoke = await revokeAppleToken({
          config: config.config,
          authorizationCode: code,
          expectedSubject: appleSubject(user),
          fetch: deps.fetch,
          nowSeconds: deps.nowSeconds?.() ?? Math.floor(Date.now() / 1000),
        });
        if (!revoke.ok) {
          console.error(
            `delete-account: revoke apple token failed for ${userId}: ${revoke.message}`,
          );
          return failure("revoke apple token");
        }
      }

      // 1-3. Delete backup files, backup_metadata rows, and the profile row.
      // Stop on the first failure and keep the auth user so the user can retry.
      const cleanup = await deleteUserData(supabaseAdmin, userId);
      if (!cleanup.ok) {
        console.error(
          `delete-account: ${cleanup.step} failed for ${userId}: ${cleanup.message}`,
        );
        return failure(cleanup.step);
      }

      // 4. Delete the auth user (must be last)
      const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(
        userId,
      );

      if (deleteError) {
        console.error(
          `delete-account: delete auth user failed for ${userId}: ${deleteError.message}`,
        );
        return failure("delete auth user");
      }

      return json({ message: "Account deleted successfully" }, 200);
    } catch (err) {
      console.error("delete-account: unexpected error", err);
      return failure("unexpected");
    }
  };
}
