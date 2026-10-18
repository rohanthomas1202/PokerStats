// Deletes a user's backup files, backup_metadata rows, and profile row.
// Kept separate from index.ts so it can be tested without a live Supabase.

// Narrow view of the supabase-js client: only the calls cleanup makes.
type Result = { error: { message: string } | null };

export interface CleanupClient {
  storage: {
    from(bucket: string): {
      list(
        prefix: string,
        options: { limit: number; offset: number },
      ): PromiseLike<Result & { data: { name: string }[] | null }>;
      remove(paths: string[]): PromiseLike<Result>;
    };
  };
  from(table: string): {
    delete(): { eq(column: string, value: string): PromiseLike<Result> };
  };
}

export type CleanupResult =
  | { ok: true; filesRemoved: number }
  | { ok: false; step: string; message: string };

// Storage `list` returns at most `limit` entries (default 100), so page
// through until a short page. Collect every path before removing anything:
// removing while paging would shift the offsets and skip files.
export async function deleteUserData(
  client: CleanupClient,
  userId: string,
  pageSize = 1000,
): Promise<CleanupResult> {
  const bucket = client.storage.from("backups");

  // Files are stored flat under {user_id}/{filename} (see init_schema.sql).
  const paths: string[] = [];
  for (let offset = 0;; offset += pageSize) {
    const { data, error } = await bucket.list(`${userId}/`, {
      limit: pageSize,
      offset,
    });
    if (error) {
      return { ok: false, step: "list backup files", message: error.message };
    }
    const page = data ?? [];
    paths.push(...page.map((f) => `${userId}/${f.name}`));
    if (page.length < pageSize) break;
  }

  for (let i = 0; i < paths.length; i += pageSize) {
    const { error } = await bucket.remove(paths.slice(i, i + pageSize));
    if (error) {
      return { ok: false, step: "remove backup files", message: error.message };
    }
  }

  const { error: metadataError } = await client
    .from("backup_metadata")
    .delete()
    .eq("user_id", userId);
  if (metadataError) {
    return {
      ok: false,
      step: "delete backup_metadata",
      message: metadataError.message,
    };
  }

  const { error: profileError } = await client
    .from("profiles")
    .delete()
    .eq("id", userId);
  if (profileError) {
    return { ok: false, step: "delete profile", message: profileError.message };
  }

  return { ok: true, filesRemoved: paths.length };
}
