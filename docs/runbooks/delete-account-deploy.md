# Runbook: Sign in with Apple secrets and delete-account deploy

This runbook is for the owner. It covers the owner steps left on #1, #6, #20 and #21: create the Apple key, set four Edge Function secrets, choose the JWT verification setting, deploy `delete-account`, and run the live check. The code is already on `main` (revocation in PR #35, hardening in PR #13, error codes in PR #96). No bot runs any of these steps.

Run every command from the repository root on a checkout of `main`. The values you fill in are `PROJECT_REF` (step 2), the `.p8` path and Key ID (step 4), the test user's ID in the live check (step 8), and a commit if you roll back (step 9). Nothing in this runbook asks you to paste a secret into a command.

You need the Supabase CLI, signed in (`supabase login`). Check the version with `supabase --version`. The deploy commands use `--use-api`, which bundles the function on Supabase's side so Docker isn't needed. If your CLI doesn't know that flag, update the CLI (`brew upgrade supabase`) or drop the flag and run Docker.

## 1. Preconditions

The redeploy must not land before #105 (the app's handling of the new error codes) has merged and shipped in the build people use. The shipped app treats 422 and 503 as a generic "try again", so without #105 a user with a mismatched Apple ID would be told to retry something that can never succeed.

Check that #105 is closed by a merged PR:

```bash
gh issue view 105 -R rohanthomas1202/PokerStats --json state,closedByPullRequestsReferences -q '.state, (.closedByPullRequestsReferences[] | "\(.number) \(.url)")'
```

Go on only if it prints `CLOSED` and a PR number, and that PR is merged (`gh pr view <number> -R rohanthomas1202/PokerStats --json state -q .state` prints `MERGED`). As of 2026-10-25, #105 is open, so this runbook can't be finished yet. Steps 2 to 4 (project, Apple key, secrets) are safe to do now. Step 4 alone changes nothing users see, because the deployed function doesn't read these secrets until step 6.

Also confirm your checkout is current:

```bash
git switch main && git pull --ff-only && git log -1 --format='%h %s'
```

## 2. Which Supabase project

**The repository can't settle this.** The app reads its project URL from `.env`, and `.env` is not in the repository. The two sources that name a ref disagree, so you have to check your own `.env`.

What the repository shows:

- The app takes `SUPABASE_URL` from `Secrets.plist`, falling back to `.env` (`PokerStats/Services/Cloud/Secrets.swift:5-16`). `Secrets.plist` is generated from `.env` by the pre-build script (`project.yml:57-93`). Without `.env` it holds the placeholder `https://YOUR_PROJECT_REF.supabase.co` (`project.yml:69`).
- `.env` and `.env.*` are gitignored (`.gitignore:60-61`), and no commit in the history has ever added a `.env` file. There is no `.env.example`, no xcconfig and no Info.plist entry with a Supabase URL, and `ci_scripts/` doesn't mention Supabase.
- `supabase/config.toml` has no `project_id` and names no ref (`supabase/config.toml:1-11` is only the `[functions.delete-account]` block). The issue text says `config.toml` uses `xukhlkjjrrwmorxtlizh`, but it doesn't.
- Release builds get `SUPABASE_URL` from the `testflight` and `app-store` GitHub environment secrets (README, Releases, Owner setup). Their values can't be read from the repository.
- For `xukhlkjjrrwmorxtlizh`: `progress.md:4-5` (project created there, "Project URL and anon key added to `.env`"), `progress.md:35` (CLI linked there), the CLI link file committed in 998c7c9 on 2026-03-14 and removed in cb18c20 (`supabase/.temp/project-ref` held `xukhlkjjrrwmorxtlizh`), `docs/specs/1.1-sync.md:19` and `docs/design/1.1-sync.md:571`.
- For `bplrxbatvglxreulodtj`: `docs/superpowers/specs/2026-04-21-delete-account-design.md:10` and `docs/superpowers/plans/2026-04-21-delete-account.md:29`. These are the only places that say what the app's `.env` contained, and they are dated 2026-04-21, after `progress.md` Step 1.

So the latest written record of the app's `.env` says `bplrxbatvglxreulodtj`, and everything else says `xukhlkjjrrwmorxtlizh`. Neither can be confirmed from the repository. Your `.env` is the answer.

Run this from the repository root on the Mac you build the app from. It reads the ref from `.env` and sets `PROJECT_REF` for the rest of this runbook:

```bash
PROJECT_REF="$(sed -nE 's#^SUPABASE_URL=["'\'']?https://([a-z0-9]+)\.supabase\.co.*#\1#p' .env)"; echo "PROJECT_REF=$PROJECT_REF"
```

If it prints nothing, `.env` is missing or `SUPABASE_URL` isn't in the usual form. Open `.env`, read the ref from the URL yourself and set it by hand, `PROJECT_REF=<ref>`.

Then check two more things against it:

```bash
# Where the CLI is linked now. The commands below pass --project-ref, so this link is not used, but it shows which project earlier deploys went to.
cat supabase/.temp/project-ref 2>/dev/null; echo
# Which of the two projects has delete-account deployed today.
supabase functions list --project-ref xukhlkjjrrwmorxtlizh
supabase functions list --project-ref bplrxbatvglxreulodtj
```

- If `PROJECT_REF` is not the project where `delete-account` is listed, the app has been calling a project without the function. Deploy to `PROJECT_REF` anyway: that is the project the app calls.
- The project in `PROJECT_REF` must be the one whose Auth holds your users, with the `profiles` and `backup_metadata` tables and the `backups` bucket. Check in the dashboard (`https://supabase.com/dashboard/project/<PROJECT_REF>`) before going on.
- The `SUPABASE_URL` secret in the `testflight` and `app-store` GitHub environments must use the same ref. GitHub won't show a secret's value. If you aren't sure, set it again (Settings > Environments > each environment > `SUPABASE_URL`).
- Once you know the answer, update `progress.md` and tell engineering (step 10, item 3). The docs that name the other ref get a "historical" note in a follow-up, and the Services ID domain in step 3 uses this ref too.

Every command from here on uses `"$PROJECT_REF"`. If you open a new terminal, set it again.

## 3. Apple key and Supabase Apple provider (#1, #21)

Do these in the Apple Developer account for team `V2QRL64JUR` (Certificates, Identifiers & Profiles). Skip any item that's already done.

1. **App ID.** Identifiers > App ID `com.rohanthomas.PokerStats` > turn on **Sign in with Apple** (primary App ID) > Save. This is the bundle ID in `project.yml:101`.
2. **Key.** Keys > **+** > name it (for example "PokerStats Sign in with Apple") > tick **Sign in with Apple** > Configure > primary App ID `com.rohanthomas.PokerStats` > Save > Continue > Register.
3. **Download** the `.p8` file (Apple lets you download it once) and note the 10-character **Key ID** shown on the key's page. Keep the file somewhere private outside the repository, for example `~/Keys/AuthKey_<KEYID>.p8`, readable only by you: `chmod 600 ~/Keys/AuthKey_*.p8`. The repository ignores `*.p8` (`.gitignore`), but don't put it in the checkout.
4. **Services ID (only for a web sign-in flow).** The iOS app signs in natively and doesn't need one. If you want web sign-in later: Identifiers > **+** > Services IDs > `com.rohanthomas.PokerStats.auth` > turn on Sign in with Apple > Configure > domain `<PROJECT_REF>.supabase.co`, return URL `https://<PROJECT_REF>.supabase.co/auth/v1/callback`. Use the ref from step 2, not whatever an older doc says.

Then in Supabase (`https://supabase.com/dashboard/project/<PROJECT_REF>/auth/providers`), open **Apple**:

1. Turn the provider on.
2. **Client IDs:** `com.rohanthomas.PokerStats`. Add `com.rohanthomas.PokerStats.auth` after it, comma-separated, only if you created the Services ID for web sign-in.
3. **Secret Key (for OAuth):** only needed for the web flow. Native iOS sign-in doesn't use it. If you fill it in, it's a client-secret JWT made from the `.p8`, and Apple caps its lifetime at 6 months, so it has to be made again before then. This is separate from the delete-account secrets in step 4, which never expire (see step 10).
4. **Skip nonce check:** leave it **off** (#21). Turning it on would let a captured Apple ID token be replayed.
5. Save. The provider should show as enabled.

## 4. Edge Function secrets (#20)

The function reads exactly these four names (`APPLE_ENV` in `supabase/functions/delete-account/apple.ts:21-26`):

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | `V2QRL64JUR` |
| `APPLE_KEY_ID` | the 10-character Key ID from step 3 |
| `APPLE_CLIENT_ID` | `com.rohanthomas.PokerStats`, the app's bundle ID (`project.yml:101`). Not the Services ID: native Sign in with Apple codes are issued to the App ID, so Apple rejects the token exchange for any other client ID (PR #35). |
| `APPLE_PRIVATE_KEY` | the full contents of the `.p8` file, including the `BEGIN` and `END` lines |

Set the path to your `.p8` file and the Key ID (neither is a secret), then set all four:

```bash
P8_PATH="$HOME/Keys/AuthKey_XXXXXXXXXX.p8"
APPLE_KEY_ID_VALUE="XXXXXXXXXX"
supabase secrets set --project-ref "$PROJECT_REF" \
  APPLE_TEAM_ID=V2QRL64JUR \
  APPLE_KEY_ID="$APPLE_KEY_ID_VALUE" \
  APPLE_CLIENT_ID=com.rohanthomas.PokerStats \
  APPLE_PRIVATE_KEY="$(cat "$P8_PATH")"
```

Why the key stays out of your shell history: the shell saves the command as you typed it, so the history holds the text `$(cat "$P8_PATH")`, not the key. The key is read from the file when the command runs. The function accepts the key with real newlines, which is what this passes, or with `\n` escapes (`apple.ts`, PR #35).

While the command runs, the key is in the `supabase` process's arguments, which other users on the same machine could see with `ps`. On your own Mac that doesn't matter. If you'd rather keep it out of the process list too, set it from a temporary env file instead:

```bash
ENV_TMP="$(umask 077; mktemp)"
printf 'APPLE_PRIVATE_KEY="%s"\n' "$(awk 'BEGIN { ORS = "\\n" } { print }' "$P8_PATH")" > "$ENV_TMP"
supabase secrets set --project-ref "$PROJECT_REF" --env-file "$ENV_TMP"
rm -f "$ENV_TMP"
```

This writes the key on one line with `\n` escapes into a file only you can read, hands the file to the CLI, and deletes it.

Confirm all four names exist (the CLI shows a digest, not the value):

```bash
supabase secrets list --project-ref "$PROJECT_REF" | grep -E 'APPLE_(TEAM_ID|KEY_ID|CLIENT_ID|PRIVATE_KEY)'
```

You should see four lines. `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected by Supabase; don't set them.

Set the secrets before you deploy (step 6). A deployed function without them returns 503 `server_not_configured` for every Apple-linked user.

## 5. JWT verification choice (#6): owner picks

`verify_jwt` controls whether Supabase's gateway checks the caller's JWT before the function runs. The two sources disagree: `supabase/config.toml:4` says `verify_jwt = true`, while #6 and `progress.md:38` say `--no-verify-jwt`, which is how the current version was deployed.

In both cases the function checks the caller itself. It passes the request's `Authorization` header to `auth.getUser()` (`supabase/functions/delete-account/handler.ts:141`), which asks Supabase Auth to validate the token. Without a header it returns 401 `{"error":"Missing authorization"}`, and with a bad token 401 `{"error":"Invalid token"}` (`handler.ts:127`, `handler.ts:144`). No data is touched before that check passes.

**Option A: `verify_jwt = true` (what `config.toml` says).**

- Command: `supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api`. With no flag, the CLI takes `verify_jwt = true` from `config.toml`.
- Requests with no token or an invalid token are rejected by the gateway with 401 before the function starts, so they don't run the function or show in its logs. Valid tokens still go through `auth.getUser()`.
- The repository and the deployed setting agree, so a later plain deploy doesn't change it.
- Supabase now calls this gateway check legacy, and it only understands the legacy JWT format. If the project has moved to the new asymmetric JWT signing keys, the gateway can reject real users' tokens, and every deletion fails with a 401 before the function runs. The app shows its generic "try again" alert for that. Check under Project Settings > JWT Keys. If the project is on the new signing keys, Option A isn't safe until that is sorted out.

**Option B: `--no-verify-jwt` (what #6 and `progress.md` say).**

- Command: `supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api --no-verify-jwt`.
- Every request reaches the function, and `auth.getUser()` is the only check. Bad requests get the function's own 401 bodies above and appear in the function's logs.
- It works the same whatever JWT keys the project uses, and it matches how the function is deployed today.
- It disagrees with `config.toml`. Any later deploy without `--no-verify-jwt`, including the rollback in step 9, silently turns the check back on. If you pick B, tell engineering so a follow-up PR can set `verify_jwt = false` under `[functions.delete-account]` in `config.toml`.

**retire-backups is separate.** `docs/design/1.1-sync.md` section 7.2 says the planned `retire-backups` cron function keeps `verify_jwt = true`. Its cron call sends the legacy JWT anon key, which passes the gateway, plus an `x-cron-secret` header. That applies to `retire-backups` only. `verify_jwt` is set per function, so whatever you pick here doesn't change it, and `retire-backups` doesn't exist yet.

Engineering's view: both options are safe for this function, because `auth.getUser()` checks the token either way. The deciding fact is which JWT signing keys the project uses (see Option A). If they're the legacy keys, either works.

Write down your choice. Step 6 deploys it, and steps 7, 9 and 10 depend on it.

## 6. Deploy

First save a copy of what's deployed now, so step 9 can put it back. The download writes into `supabase/functions/delete-account/` under the folder it's given, so point it at a separate folder or it overwrites your checkout:

```bash
DEPLOY_COMMIT="$(git rev-parse HEAD)"; echo "Deploying $DEPLOY_COMMIT"
supabase functions list --project-ref "$PROJECT_REF" | tee "$HOME/delete-account-before-$(date +%Y%m%d).txt"
mkdir -p "$HOME/delete-account-backup/supabase"
supabase functions download delete-account --project-ref "$PROJECT_REF" --use-api --workdir "$HOME/delete-account-backup"
cp supabase/config.toml "$HOME/delete-account-backup/supabase/config.toml"
ls -R "$HOME/delete-account-backup/supabase"
```

The download holds only the function's files, not `config.toml`, so the `cp` line puts this checkout's `supabase/config.toml` next to them for the rollback in step 9. The listing should show `config.toml` and, under `functions/delete-account/`, at least `index.ts` and `deno.json`.

If the download fails because the function doesn't exist on `PROJECT_REF`, there's nothing to roll back to; carry on.

Then run the one command for your choice, from the repository root on `main`:

```bash
# Option A: verify_jwt = true (from config.toml)
supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api
```

```bash
# Option B: --no-verify-jwt
supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api --no-verify-jwt
```

Check it landed:

```bash
supabase functions list --project-ref "$PROJECT_REF"
```

`delete-account` should show `ACTIVE`, a version one higher than before, and an `UPDATED_AT` from a moment ago. The dashboard (Edge Functions > delete-account > Details) shows whether "Verify JWT with legacy secret" is on, which should match your choice.

## 7. Safe smoke checks

These requests delete nothing: they carry no valid user token, so they stop before any deletion. Set the URL once:

```bash
FN_URL="https://$PROJECT_REF.supabase.co/functions/v1/delete-account"
```

No `Authorization` header:

```bash
curl -sS -i -X POST "$FN_URL"
```

A malformed token:

```bash
curl -sS -i -X POST "$FN_URL" -H "Authorization: Bearer not-a-real-token"
```

Expected results:

| Check | Option A: `verify_jwt = true` | Option B: `--no-verify-jwt` |
|---|---|---|
| No `Authorization` header | 401 from the gateway: `{"code":401,"message":"Missing authorization header"}` | 401 from the function: `{"error":"Missing authorization"}` (`handler.ts:127`) |
| Malformed token | 401 from the gateway: `{"code":401,"message":"Invalid JWT"}` | 401 from the function: `{"error":"Invalid token"}` (`handler.ts:144`) |

The Option A bodies come from the gateway, not from this repository, so they're as given in Supabase's "Edge Function 401 error response" guide (https://supabase.com/docs/guides/troubleshooting/edge-function-401-error-response). The exact text can change between platform versions: newer runtimes also send a `msg` field with the same text and an `sb-error-code` header, and Supabase's guide also lists `"Invalid Token or Protected Header formatting"` for a bad token. What matters is the status (401) and that the body is the gateway's `code`/`message` form, not the function's `{"error": ...}` form. If you see the function's body under Option A, or the gateway's under Option B, the deployed setting isn't the one you picked; redeploy with the right command from step 6.

Other results:

- 404 means the function isn't deployed on `PROJECT_REF`. Check step 2 and redo step 6.
- 5xx on these checks means the function failed to start. Read the logs (Edge Functions > delete-account > Logs).

These checks can't reach the codes in the #105 table. Those only come back for a signed-in user, and step 8 covers them.

## 8. Live check (#20 acceptance)

Use a throwaway account, not your real one: a test Apple ID, or your Apple ID on a fresh account with nothing you want to keep. It must be an Apple-linked account, since that's what the revocation path covers.

1. On a physical iPhone with a build that includes #105, sign in to PokerStats with Sign in with Apple. Make one backup in Settings so there's a file under `backups/<userId>/`.
2. In the Supabase dashboard (Authentication > Users), find the new user and copy its user ID. You'll use it in the queries below; don't paste it into any repository file, issue or PR.
3. On the iPhone, confirm PokerStats is listed under Settings > [your name] > Sign-In & Security > Sign in with Apple.
4. In the app: Settings > Delete Account, confirm both alerts, then confirm with Apple when the Apple sheet appears.
5. The app should sign out and return to the sign-in screen with local data wiped.

Then confirm everything is gone:

- **Apple:** PokerStats no longer appears under Sign in with Apple on the iPhone (or at https://account.apple.com > Sign-In and Security > Sign in with Apple). It can take a minute to update.
- **Supabase:** in the SQL Editor for `PROJECT_REF`, replace `<USER_ID>` and run. These only read. Each count should be 0:

```sql
select
  (select count(*) from auth.users where id = '<USER_ID>') as auth_users,
  (select count(*) from public.profiles where id = '<USER_ID>') as profiles,
  (select count(*) from public.backup_metadata where user_id = '<USER_ID>') as backup_metadata,
  (select count(*) from storage.objects where bucket_id = 'backups' and name like '<USER_ID>/%') as backup_files;
```

- **Logs:** Edge Functions > delete-account > Logs shows the request with status 200 and no `delete-account:` error lines. The function only logs on failure, so an empty log for that request is normal.

If the deletion fails, the response code tells you what happened. Every failure body is `{ error, code, retryable, step, apple_revoked? }` (`handler.ts:61-115`). The app's alert for each code below is the copy agreed on #105; check the merged #105 PR for the final wording.

| HTTP | `code` | What it means | Expected alert in the app |
|---|---|---|---|
| 400 | `apple_reauth_required` | The app sent no Apple authorization code. The app shows the Apple sheet and retries once; a second 400 is treated as `delete_failed`. | Apple sheet, then none if the retry works |
| 422 | `apple_account_mismatch` | The Apple ID chosen in the sheet isn't the one this account signed in with. Nothing deleted. | "This Apple ID doesn't match your account. Delete again and choose the Apple ID you signed in with." No Try Again. |
| 422 | `apple_identity_missing` | Supabase has no Apple user ID on file for this account. Nothing deleted. | "Your account couldn't be deleted. Contact support at [CONTACT_EMAIL]." No Try Again. |
| 422 | `apple_token_invalid` | Apple's token had the wrong issuer or audience. Usually `APPLE_CLIENT_ID` isn't the bundle ID. Nothing deleted. | "Your account couldn't be deleted. Contact support at [CONTACT_EMAIL]." No Try Again. |
| 503 | `server_not_configured` | A secret is missing or the private key can't be read. The log names the missing secrets, never values. Nothing deleted. Redo step 4. | "Account deletion is temporarily unavailable. Your account wasn't deleted. Try again later." Try Again shown. |
| 500 | `delete_failed` | Apple token exchange or revoke error, network, a cleanup step, the auth user delete, or something unexpected. `step` says where. | The generic "Couldn't Delete Account" alert with Try Again. |
| any failure with `apple_revoked: true` | | Apple was disconnected, then a cleanup step failed. The account and remaining data are kept. | "Couldn't Finish Deleting Account": sign in with Apple again, then try again. |

`[CONTACT_EMAIL]` is a placeholder until the support address is picked (#76).

For a 500, the function log line starting `delete-account:` gives the step and, for Apple errors, Apple's HTTP status and error code. No secrets, codes or tokens are logged.

## 9. Rollback

Secrets stay set through a rollback or redeploy. `supabase functions deploy` doesn't touch them, so there's no need to set them again.

Option 1, go back to an earlier commit of this repository. Use a separate worktree so your checkout isn't touched, and pass the same `verify_jwt` flag you deployed with (step 5):

```bash
ROLLBACK_COMMIT="<commit to go back to>"
git fetch origin && git worktree add "/tmp/pokerstats-rollback" "$ROLLBACK_COMMIT"
cd /tmp/pokerstats-rollback
# Option A:
supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api
# Option B:
supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api --no-verify-jwt
cd - && git worktree remove /tmp/pokerstats-rollback
```

Run only the deploy line for your option. Under Option A, the CLI reads `verify_jwt` from that commit's `config.toml`, so check it there first: `git show "$ROLLBACK_COMMIT":supabase/config.toml`.

Option 2, put back the exact version that was deployed before step 6, from the copy saved there. Run the line for your option from step 5, from the repository root:

```bash
ls "$HOME/delete-account-backup/supabase/config.toml" "$HOME/delete-account-backup/supabase/functions/delete-account/index.ts" "$HOME/delete-account-backup/supabase/functions/delete-account/deno.json"
# Option A:
supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api --workdir "$HOME/delete-account-backup"
# Option B:
supabase functions deploy delete-account --project-ref "$PROJECT_REF" --use-api --no-verify-jwt --workdir "$HOME/delete-account-backup"
```

With `--workdir`, the CLI reads `config.toml` from `$HOME/delete-account-backup/supabase/`, not from your checkout. That is why step 6 copies it there: it sets `import_map = "./functions/delete-account/deno.json"` and `entrypoint = "./functions/delete-account/index.ts"` (`supabase/config.toml:5-8`), and under Option A it supplies `verify_jwt`. This `config.toml` hasn't changed since the version deployed before this runbook (998c7c9), so it matches how that version was built. If the `ls` line reports a missing `config.toml`, step 6's `cp` didn't run; write the one that version was built with, `git show 998c7c9:supabase/config.toml > "$HOME/delete-account-backup/supabase/config.toml"`, and run `ls` again. If it reports a missing `index.ts` or `deno.json`, the download isn't in the layout the config expects, so don't deploy from it: use Option 1 with the commit closest to that version.

The version deployed before this runbook went out with `--no-verify-jwt` (`progress.md:38`). Option B restores that setting. Option A deploys the old code with the gateway check on.

Rolling back to any version before PR #35 removes Apple token revocation, which App Review requires (5.1.1(v)). Treat that as a short-term fix only.

## 10. After

1. In `progress.md`, add a line under Step 6 for the redeploy, with the date, the `verify_jwt` choice and `$DEPLOY_COMMIT` from step 6. Tick the Step 4 boxes that step 3 covered.
2. Comment on #6 and #20 with the date, the deploy setting and the commit, for example:

   ```bash
   gh issue comment 6 -R rohanthomas1202/PokerStats --body "delete-account redeployed on $(date +%Y-%m-%d) to the app's project from $DEPLOY_COMMIT with <verify_jwt = true | --no-verify-jwt>. Smoke checks and the live check in docs/runbooks/delete-account-deploy.md passed."
   gh issue comment 20 -R rohanthomas1202/PokerStats --body "Apple secrets set and delete-account redeployed on $(date +%Y-%m-%d) from $DEPLOY_COMMIT with <verify_jwt = true | --no-verify-jwt>. Live check passed: PokerStats removed from the test Apple ID's Sign in with Apple list, and the user, profile and backups are gone."
   ```

   Replace the `<...>` part with your choice before running. Close #1, #6, #20 and #21 when their acceptance items are met; this runbook doesn't close them by itself.
3. Once you know which project ref is right (step 2), update the Step 1 line in `progress.md`: name that ref and remove the "unconfirmed" note. Then tell engineering, so the docs that name the other ref (`docs/superpowers/specs/2026-04-21-delete-account-design.md`, `docs/superpowers/plans/2026-04-21-delete-account.md`, `docs/specs/1.1-sync.md`, `docs/design/1.1-sync.md`) get marked historical.
4. **Key lifetime.** Apple allows a client-secret JWT to live up to 6 months. `delete-account` doesn't store one: it mints a fresh one from the `.p8` on every call, valid for 5 minutes (`exp = iat + 300`, PR #35). So nothing needs rotating for this function unless the `.p8` key is revoked in the Apple Developer account. If you ever revoke it, create a new key (step 3), set `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` again (step 4), and run the step 7 checks. The 6-month limit only applies to the Supabase Apple provider's "Secret Key (for OAuth)" for a web flow, if you set one (step 3).
