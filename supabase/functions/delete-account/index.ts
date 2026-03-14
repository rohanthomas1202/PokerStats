import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  // Only allow POST
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Extract user from JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Create admin client for privileged operations
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Create user client to identify the caller
    const supabaseUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const userId = user.id;

    // 1. Delete backup files from storage
    const { data: files } = await supabaseAdmin.storage
      .from("backups")
      .list(`${userId}/`);

    if (files && files.length > 0) {
      const filePaths = files.map((f) => `${userId}/${f.name}`);
      await supabaseAdmin.storage.from("backups").remove(filePaths);
    }

    // 2. Delete backup metadata rows
    await supabaseAdmin
      .from("backup_metadata")
      .delete()
      .eq("user_id", userId);

    // 3. Delete profile row
    await supabaseAdmin.from("profiles").delete().eq("id", userId);

    // 4. Delete the auth user (must be last)
    const { error: deleteError } =
      await supabaseAdmin.auth.admin.deleteUser(userId);

    if (deleteError) {
      return new Response(
        JSON.stringify({ error: `Failed to delete user: ${deleteError.message}` }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({ message: "Account deleted successfully" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message ?? "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
