-- PokerStats initial schema
-- Tables: profiles, backup_metadata
-- Storage bucket: backups
-- Trigger: auto-create profile row on new auth user

-- ============================================================
-- profiles: per-user metadata mirrored from auth.users
-- ============================================================
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    last_backup_at timestamptz,
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
    on public.profiles for select
    using (auth.uid() = id);

create policy "profiles_insert_own"
    on public.profiles for insert
    with check (auth.uid() = id);

create policy "profiles_update_own"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

create policy "profiles_delete_own"
    on public.profiles for delete
    using (auth.uid() = id);

-- Auto-insert profile row when a new auth user is created
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ============================================================
-- backup_metadata: one row per cloud backup upload
-- ============================================================
create table if not exists public.backup_metadata (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    storage_path text not null,
    file_size_bytes bigint not null,
    schema_version integer not null,
    session_count integer not null,
    hand_count integer not null,
    created_at timestamptz not null default now()
);

create index if not exists backup_metadata_user_id_created_at_idx
    on public.backup_metadata (user_id, created_at desc);

alter table public.backup_metadata enable row level security;

create policy "backup_metadata_select_own"
    on public.backup_metadata for select
    using (auth.uid() = user_id);

create policy "backup_metadata_insert_own"
    on public.backup_metadata for insert
    with check (auth.uid() = user_id);

create policy "backup_metadata_delete_own"
    on public.backup_metadata for delete
    using (auth.uid() = user_id);

-- ============================================================
-- Storage bucket: backups (private, user-scoped)
-- ============================================================
insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do nothing;

-- Files are stored under {user_id}/{filename}
-- Allow users to CRUD only files under their own folder
create policy "backups_select_own"
    on storage.objects for select
    using (
        bucket_id = 'backups'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "backups_insert_own"
    on storage.objects for insert
    with check (
        bucket_id = 'backups'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "backups_update_own"
    on storage.objects for update
    using (
        bucket_id = 'backups'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

create policy "backups_delete_own"
    on storage.objects for delete
    using (
        bucket_id = 'backups'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
