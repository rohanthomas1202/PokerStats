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
      ): PromiseLike<
        Result & { data: { name: string; id: string | null }[] | null }
      >;
      remove(paths: string[]): PromiseLike<Result>;
    };
  };
  from(table: string): {
    delete(): { eq(column: string, value: string): PromiseLike<Result> };
  };
}

// Storage remove batch size, independent of the list page size.
export const REMOVE_BATCH = 1000;

export type CleanupResult =
  | { ok: true; filesRemoved: number }
  | { ok: false; step: string; message: string };

// Folders nested deeper than this fail the step instead of recursing forever
// (e.g. a storage bug that keeps returning the same folder).
export const MAX_DEPTH = 32;

type Bucket = ReturnType<CleanupClient["storage"]["from"]>;
type ListResult = { ok: true; files: string[] } | {
  ok: false;
  message: string;
};

// Lists every file under `prefix` (which ends in "/"), recursing into folder
// entries (id === null). Storage `list` returns at most `limit` entries
// (default 100), so each level is paged until a short page. A level's folders
// are only visited after that level is fully listed.
async function listFilesRecursive(
  bucket: Bucket,
  prefix: string,
  pageSize: number,
  depth = 0,
): Promise<ListResult> {
  if (depth > MAX_DEPTH) {
    return {
      ok: false,
      message: `folders nested deeper than ${MAX_DEPTH} at ${prefix}`,
    };
  }
  const files: string[] = [];
  const folders: string[] = [];
  for (let offset = 0;; offset += pageSize) {
    const { data, error } = await bucket.list(prefix, {
      limit: pageSize,
      offset,
    });
    if (error) return { ok: false, message: error.message };
    const page = data ?? [];
    for (const entry of page) {
      if (entry.id === null) folders.push(`${prefix}${entry.name}/`);
      else files.push(`${prefix}${entry.name}`);
    }
    if (page.length < pageSize) break;
  }
  for (const folder of folders) {
    const sub = await listFilesRecursive(bucket, folder, pageSize, depth + 1);
    if (!sub.ok) return sub;
    files.push(...sub.files);
  }
  return { ok: true, files };
}

// Collect every path before removing anything: removing while paging would
// shift the offsets and skip files.
export async function deleteUserData(
  client: CleanupClient,
  userId: string,
  pageSize = 1000,
): Promise<CleanupResult> {
  const bucket = client.storage.from("backups");

  // The app stores files flat under {user_id}/{filename} (see
  // init_schema.sql), but anything nested under the prefix is removed too.
  const prefix = `${userId}/`;
  const listed = await listFilesRecursive(bucket, prefix, pageSize);
  if (!listed.ok) {
    return { ok: false, step: "list backup files", message: listed.message };
  }
  const paths = listed.files;

  for (let i = 0; i < paths.length; i += REMOVE_BATCH) {
    const { error } = await bucket.remove(paths.slice(i, i + REMOVE_BATCH));
    if (error) {
      return { ok: false, step: "remove backup files", message: error.message };
    }
  }

  // A short page before the real end would stop the listing early, and a
  // backup uploaded mid-deletion would survive, so list the whole tree again
  // and confirm nothing is left before touching the database rows.
  const left = await listFilesRecursive(bucket, prefix, pageSize);
  if (!left.ok) {
    return {
      ok: false,
      step: "verify backup files removed",
      message: left.message,
    };
  }
  if (left.files.length > 0) {
    return {
      ok: false,
      step: "verify backup files removed",
      message: `${left.files.length}+ files still under ${prefix}`,
    };
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
