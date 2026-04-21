# Delete Account — Design Spec

**Date:** 2026-04-21
**Status:** Approved, ready for implementation plan

## Problem

Tapping **Delete Account** in Settings surfaces two confirmation alerts, but the final "Yes, Delete My Account" button silently does nothing the user can perceive. Investigation found multiple layered defects:

1. **Backend not reachable.** The Supabase CLI is linked to project `xukhlkjjrrwmorxtlizh`, but the app's `.env` points to `bplrxbatvglxreulodtj`. Any prior `supabase functions deploy` ran against the wrong project, so `delete-account` almost certainly does not exist on the project the app calls.
2. **Errors swallowed.** `AuthViewModel.deleteAccount()` catches the failure into `errorMessage`, but `SettingsView` has no UI bound to that field, so the user sees nothing.
3. **No success feedback.** On the happy path `isAuthenticated` flips and the Delete Account button disappears, but there is no explicit "Account deleted" signal.
4. **Parallel cloud + local wipes.** The final alert button runs `authViewModel?.deleteAccount()` (async) and `viewModel.deleteAllData(...)` (sync) concurrently. If the cloud call fails, local data has already been erased — user loses data but still has a live server account.
5. **Incomplete local wipe.** `SettingsViewModel.deleteAllData` only deletes `Hand` and `Session`; `Settings` and `TableConfig` rows persist after "account deletion".
6. **Apple credential not revoked.** App Store guideline 5.1.1(v) requires revoking the Apple token on account delete for users who signed in with Apple. The current code concedes this via a comment and does not do it.

## Goals

- Tapping "Yes, Delete My Account" produces a visible, correct outcome: either a fully-deleted account + cleared local data, or an actionable error alert.
- Cloud deletion is authoritative. Local data is only wiped after the server confirms the account is gone.
- The Edge Function exists and is reachable on the Supabase project the app actually uses.

## Non-Goals

- **Apple credential revocation.** Calling `appleid.apple.com/auth/revoke` requires persisting the Apple authorization code from the initial sign-in, which the current schema does not store. Tracked as a follow-up compliance item; not in scope for this change.
- **Undo / grace period.** Deletion is immediate and irreversible, matching the current UX intent.
- **Success toast or confirmation alert.** User preference (option C): silent success, alert only on failure.
- **New confirmation steps.** The existing two-alert chain stays as-is.

## Design

### Ownership

`AuthService.deleteAccount(modelContext:)` becomes the single entry point. It orchestrates all four phases. The view layer calls this one method and handles only UI state (loading spinner, error alert).

### Ordered deletion pipeline

1. **Cloud** — `SupabaseClient.callEdgeFunction("delete-account")`. On non-2xx, throw `SupabaseError.httpError` with the server's message. The Edge Function already performs: delete backup files → delete `backup_metadata` rows → delete `profiles` row → `auth.admin.deleteUser`. No change to the function itself.
2. **Keychain** — `KeychainHelper.deleteAll()`.
3. **Local SwiftData** — delete all rows of `Hand`, `Session`, `Settings`. Save the context. Reload widget timelines via `WidgetCenter.shared.reloadAllTimelines()`.
4. **In-memory auth state** — `isAuthenticated = false`, clear `userId` / `userEmail`.

If step 1 throws, the pipeline stops and re-throws. Steps 2–4 do not execute; local data is preserved. This means a user facing a transient server error can retry without having lost their hand history.

Steps 2–4 are best-effort once step 1 succeeds; they should not throw. If a local save fails (e.g., SwiftData write error after the server has already deleted the account), it is logged and swallowed — the account is gone on the server, so the user must be treated as signed out regardless.

### View-model changes

`AuthViewModel.deleteAccount(modelContext:)` grows a `modelContext: ModelContext` parameter. It sets `isProcessing = true`, awaits `authService.deleteAccount(modelContext:)`, and on failure populates `errorMessage` with `error.localizedDescription`. `isProcessing` drops in a `defer`.

### View changes

`SettingsView`:

- Final alert's destructive button changes from two calls (`authViewModel?.deleteAccount()` + `viewModel.deleteAllData(...)`) to one: `authViewModel?.deleteAccount(modelContext: modelContext)`.
- Add a new `.alert("Couldn't delete account", isPresented: <binding to errorMessage non-nil>)` that reads `authViewModel?.errorMessage ?? ""`. OK clears the message.
- No loading indicator in the MVP — the final alert dismisses immediately on tap, and `isAuthenticated` flipping will remove the Delete Account button. If the call takes long enough to be noticeable and fails, the error alert appears on return; if it succeeds, the Settings screen updates silently as specified.

`SettingsViewModel.deleteAllData(...)` is no longer called from the Delete Account flow. It remains for the "Delete All Data" button (local-only wipe for signed-out users), unchanged.

### Backend deployment

One-time setup outside the Xcode project:

```
supabase link --project-ref bplrxbatvglxreulodtj
supabase functions deploy delete-account
```

`SUPABASE_SERVICE_ROLE_KEY` is auto-available to Edge Functions on the platform; no secrets to set manually. Verify the function is enabled in the Supabase dashboard's Functions section after deploy.

## Files Changed

| File | Change |
|------|--------|
| `PokerStats/Services/Auth/AuthService.swift` | `deleteAccount` takes `ModelContext`, performs ordered pipeline |
| `PokerStats/ViewModels/AuthViewModel.swift` | `deleteAccount` takes `ModelContext`, populates `errorMessage` on throw |
| `PokerStats/Views/Settings/SettingsView.swift` | Final alert calls single method; new error alert bound to `errorMessage` |
| `supabase/functions/delete-account/*` | No code change; deployed to correct project |

No changes to `project.yml`, entitlements, Edge Function source, or schema.

## Testing

- **Happy path:** sign in → create a session → tap Delete Account through both alerts. Verify: (a) user signed out, (b) Sessions list empty on return, (c) Supabase dashboard shows no user row, no `profiles` row, no backup files for the deleted user ID.
- **Cloud failure:** simulate by signing the Edge Function off (or tampering the token). Expect: error alert with server message, local data intact, still signed in.
- **Offline:** airplane mode during deletion. Expect: network error alert, no local data loss.
- **Anon-key fallback:** confirm `Secrets.plist` contains correct values after build (regression check for the previously-fixed sandbox bug).

## Known Follow-ups

- **Apple token revocation** (App Store 5.1.1(v)). Requires persisting Apple's authorization code on first sign-in and a server-side revoke call. Track as its own phase before App Store submission.
