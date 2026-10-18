import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { makeHandler } from "./handler.ts";

// Clients are assigned to a const before returning: returning createClient()
// directly into the typed slot makes tsc give up (TS2589).
Deno.serve(makeHandler({
  createAdminClient() {
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    return client;
  },
  createUserClient(authHeader) {
    const client = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    return client;
  },
}));
