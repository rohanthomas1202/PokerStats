// Request handler for delete-account, with the Supabase clients injected so
// the HTTP contract can be tested without a live project.
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
      data: { user: { id: string } | null };
      error: AuthError;
    }>;
  };
}

export interface HandlerDeps {
  createAdminClient(): AdminClient;
  createUserClient(authHeader: string): UserClient;
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
