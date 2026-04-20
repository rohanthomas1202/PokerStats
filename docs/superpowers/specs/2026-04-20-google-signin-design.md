# Google Sign-In Integration — Design

**Date:** 2026-04-20
**Author:** Rohan Thomas (with Claude)
**Status:** Approved — ready for implementation plan

## Context

The PokerStats iOS app (submitted to App Store as "PokerIntel") was rejected under App Review Guideline 2.1 for missing review-information. Alongside addressing that rejection, we want to complete the sign-in surface area that currently ships a non-functional Google button.

Current state of auth (verified 2026-04-20):
- **Apple Sign In** — fully wired end-to-end via `SignInWithAppleButton` → `AuthViewModel.handleAppleSignIn` → `AuthService.signInWithApple` → Supabase `/auth/v1/token?grant_type=id_token`. Credential revocation observed in `AuthService.initialize()`.
- **Email/password** — fully wired.
- **Google Sign-In** — placeholder only. Button exists in `SignInView.swift:105-119`; `AuthViewModel.handleGoogleSignIn()` (lines 91-96) just sets an error message.
- **Delete Account** — fully wired in `SettingsView.swift:104-110` with two-step confirmation; calls Supabase Edge Function `delete-account` which exists at `supabase/functions/delete-account/`.

Only Google requires new work. Apple and delete-account are already complete.

## Goal

Replace the Google Sign-In stub with a working implementation using Google's official `GoogleSignIn-iOS` SDK, such that tapping "Sign in with Google" presents the native Google bottom sheet, completes OAuth, and establishes a Supabase session using the ID token Google returns.

## Non-Goals

- Silent re-sign-in on app launch (our own Keychain-based session restore handles this).
- Google Drive backup.
- Account linking across providers (if a Google email matches an existing Apple-linked user, Supabase treats them as distinct users; cross-provider linking is a larger feature deferred to a later milestone).
- Unit tests for the OAuth flow (UI-bound and SDK-mediated; manual device testing only).
- Updating the Apple Sign-In or Delete Account paths — both already work.

## Prerequisites (assumed complete per user confirmation)

- Google Cloud Console OAuth 2.0 **iOS** client ID created; bundle ID set to `com.rohanthomas.PokerStats`.
- Google Cloud Console OAuth 2.0 **Web** client ID created.
- Supabase Auth → Providers → Google enabled, using the **Web** client ID + secret (not the iOS one — Supabase uses web creds to verify the ID token the iOS SDK returns).
- `GOOGLE_CLIENT_ID` entry populated in `.env` with the **iOS** client ID.

## Design

### Dependency

Add `https://github.com/google/GoogleSignIn-iOS` via Swift Package Manager, pinned to the latest stable major version, scoped to the `PokerStats` application target only (not the `PokerStatsWidgets` extension or test targets).

### Info.plist migration

Currently `project.yml:99` sets `GENERATE_INFOPLIST_FILE: YES` for the app target, and all Info.plist keys are expressed as `INFOPLIST_KEY_*` build settings. This works for scalar values but cannot express `CFBundleURLTypes`, which is an array of dictionaries.

Switch the `PokerStats` target to an explicit Info.plist managed via XcodeGen's `info:` block (same pattern already used by `PokerStatsWidgets` at `project.yml:132-137`). Create `PokerStats/Info.plist` containing:

- Everything currently expressed via `INFOPLIST_KEY_*` (orientations, launch screen generation, ITSAppUsesNonExemptEncryption, Mac Catalyst opt-out, Live Activities support).
- `CFBundleURLTypes` — one URL type whose `CFBundleURLSchemes` contains the reversed-client-ID string for the **iOS** OAuth client (e.g. `com.googleusercontent.apps.<digits>-<hash>`).

Remove the now-redundant `INFOPLIST_KEY_*` lines and `GENERATE_INFOPLIST_FILE: YES` from `project.yml`.

### Google client ID loading

Add `googleClientID: String` to `PokerStats/Services/Cloud/Secrets.swift`, reading `GOOGLE_CLIENT_ID` from the bundled `Secrets.plist`. The existing pre-build script at `project.yml:51-89` already pulls this key from `.env` into `Secrets.plist`, so no build-pipeline changes are needed.

This keeps the client ID out of source control and matches the existing pattern for `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

### SDK configuration at launch

In `PokerStats/App/PokerStatsApp.swift`:

- Add `import GoogleSignIn`.
- In `init()` after `container` is created, call `GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Secrets.googleClientID)`.
- Add `.onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }` to the `ContentView` modifier chain so OAuth callback URLs are forwarded to the SDK.

Do not call `restorePreviousSignIn` — our own Keychain-based session restore in `AuthService.initialize()` is the source of truth.

### Sign-in flow

Replace the stub in `AuthViewModel.handleGoogleSignIn()` with the real flow:

1. Resolve the presenting `UIViewController`. Get the first connected `UIWindowScene`'s key window's `rootViewController`. If unavailable, set `errorMessage` and return.
2. `isProcessing = true`, clear `errorMessage`.
3. In a `Task`:
   - `let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)`
   - `guard let idToken = result.user.idToken?.tokenString else { throw AuthServiceError.googleSignInFailed("No ID token returned") }`
   - `try await authService.signInWithGoogle(idToken: idToken)` — this already exists in `AuthService.swift:89-108` and already hits Supabase correctly.
   - On success: `isShowingSignIn = false`.
4. Catch `GIDSignInError` with code `.canceled` as a silent no-op (mirrors the Apple pattern in `AuthViewModel.swift:52-53`).
5. Other errors → set `errorMessage` to the localized description.
6. `isProcessing = false` in a `defer` or in both success/failure branches.

### Sign-out

In `AuthService.signOut()` (currently `AuthService.swift:148-159`), add `GIDSignIn.sharedInstance.signOut()` before or after the Keychain wipe so the Google SDK's own cached identity is cleared too. This prevents surprise "still signed in as X" behavior on next sign-in attempt.

Requires the same `import GoogleSignIn` at the top of `AuthService.swift`.

### README update

Update `README.md` to replace the "Zero dependencies" badge and the zero-deps row in the Tech Stack table with honest phrasing: one optional dependency (`GoogleSignIn-iOS`) used only when the user taps "Sign in with Google". Retain the note that no analytics/tracking SDKs are included. Also update the zero-deps mention in the Contributing section.

This matters because App Review can fact-check marketing claims against the actual binary.

## Data flow

```
User taps Google button
  → AuthViewModel.handleGoogleSignIn()
  → GIDSignIn.sharedInstance.signIn(withPresenting:)  [native Google sheet]
  → Google returns GIDSignInResult with user.idToken
  → AuthService.signInWithGoogle(idToken:)
  → SupabaseClient.signInWithIdToken(provider: .google, idToken:)
  → Supabase returns AuthSession
  → AuthService.storeSession()  [Keychain]
  → isAuthenticated = true  [triggers autoRestoreIfEmpty in PokerStatsApp]
```

## Error handling

| Failure mode | Behavior |
|--------------|----------|
| User cancels Google sheet | Silent no-op; `errorMessage` stays nil |
| No presenting view controller | `errorMessage = "Unable to present sign-in"`; log |
| Google returns no ID token | Throw `AuthServiceError.googleSignInFailed("No ID token returned")` |
| Supabase rejects the ID token | Existing `AuthService.signInWithGoogle` catch already wraps as `googleSignInFailed` with Supabase's message |
| Network failure | Propagated as `googleSignInFailed` via localized description |

## Testing

- **No unit tests added.** `GIDSignIn` is a global singleton with UIKit dependencies; mocking it would test the mock, not the integration.
- **Manual device test plan** (to be run on a physical iPhone before the App Store resubmission):
  1. Tap Google button on `SignInView` → native Google sheet appears.
  2. Complete sign-in with a test Google account → app returns to foreground signed in.
  3. Verify `authService.isAuthenticated == true` and `userEmail` populated.
  4. Create a session, log a hand, confirm Supabase backup works.
  5. Sign out → confirm re-sign-in with the same account works without showing a stale cached identity.
  6. Regression: Apple Sign In still works. Email/password still works. Delete Account still works.

## Risks & Open Questions

1. **Bundle ID mismatch** — if the Google iOS OAuth client's bundle ID doesn't match `com.rohanthomas.PokerStats` exactly, the sheet errors immediately. User has confirmed configuration is complete (answer "A" to Question 2).
2. **Web vs. iOS client ID confusion** — Supabase needs the Web credentials; the Info.plist URL scheme needs the iOS credentials' reversed form. Both must be right.
3. **XcodeGen Info.plist migration** — moving from generated to explicit may shift a setting accidentally. Implementation plan must enumerate every current `INFOPLIST_KEY_*` on the `PokerStats` target and verify each has a corresponding key in the new plist.
4. **App Store review optics** — adding a functional Google button strengthens the resubmission; a broken Google button would have been a likely 2.1 re-rejection. This change reduces risk, not adds it.

## Explicitly out of scope

- Account linking across providers.
- Google Drive-based backup.
- Silent re-authentication via `GIDSignIn.restorePreviousSignIn`.
- Changes to Apple Sign-In or Delete Account (already complete).
- Hiding the Google button as a fallback (the user explicitly chose to implement it).
