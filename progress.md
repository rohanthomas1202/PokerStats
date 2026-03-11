# Auth & Cloud Backup — Setup Progress

## Step 1: Create Supabase Project — DONE
- Project created at https://xukhlkjjrrwmorxtlizh.supabase.co
- Project URL and anon key added to `.env`

## Step 2: Run SQL Migrations — DONE
- `profiles` table + RLS + auto-create trigger
- `backup_metadata` table + RLS + index
- `set_updated_at` trigger function

## Step 3: Create Storage Bucket — DONE
- `backups` bucket created (private, 50MB limit)
- 4 RLS policies added (SELECT, INSERT, UPDATE, DELETE) scoped to `backups/{user_id}/`

## Step 4: Configure Sign in with Apple — TODO
- [ ] Enable Sign in with Apple on App ID (`com.rohanthomas.PokerStats`) in Apple Developer Portal
- [ ] Create Services ID (`com.rohanthomas.PokerStats.auth`)
- [ ] Configure Services ID: domain = `xukhlkjjrrwmorxtlizh.supabase.co`, return URL = `https://xukhlkjjrrwmorxtlizh.supabase.co/auth/v1/callback`
- [ ] Generate Apple private key (.p8) under Keys
- [ ] Enable Apple provider in Supabase Auth with: Client ID (bundle ID), .p8 key contents, Key ID, Team ID

## Step 5: Configure Google Sign-In — TODO
- [ ] Create Google Cloud project
- [ ] Set up OAuth consent screen (External)
- [ ] Create iOS OAuth client ID (bundle ID: `com.rohanthomas.PokerStats`)
- [ ] Create Web OAuth client ID (redirect URI: `https://xukhlkjjrrwmorxtlizh.supabase.co/auth/v1/callback`)
- [ ] Enable Google provider in Supabase Auth with Web client ID/secret + iOS client ID
- [ ] Add GoogleSignIn SPM package to Xcode project
- [ ] Add reversed client ID URL scheme to project.yml
- [ ] Wire up `GIDSignIn` in AuthViewModel + PokerStatsApp

## Step 6: Deploy delete-account Edge Function — TODO
- [ ] Install Supabase CLI (`brew install supabase/tap/supabase`)
- [ ] `supabase login` + `supabase link --project-ref xukhlkjjrrwmorxtlizh`
- [ ] `supabase functions new delete-account`
- [ ] Add function code (see plan file Section 2.4)
- [ ] `supabase functions deploy delete-account --no-verify-jwt`

## Step 7: End-to-End Testing — TODO
- [ ] Sign in with Apple → verify Keychain + Supabase dashboard user
- [ ] Sign in with Google → same
- [ ] Create backup → verify Storage blob + backup_metadata row
- [ ] Restore from backup → verify data integrity
- [ ] Delete account → verify full cleanup (Supabase + local)
