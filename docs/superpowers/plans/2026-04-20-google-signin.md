# Google Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the non-functional Google Sign-In stub in PokerStats with a working implementation using Google's official `GoogleSignIn-iOS` SDK, so the App Store resubmission (Guideline 2.1) ships with all three advertised sign-in methods working.

**Architecture:** Add `GoogleSignIn-iOS` via SPM. Switch the app target from a generated Info.plist to an explicit one to accommodate `CFBundleURLTypes` (the Google OAuth callback URL scheme, an array of dicts that can't be expressed via `INFOPLIST_KEY_*`). Configure `GIDSignIn` at launch using the client ID already loaded from `Secrets.plist`. In the sign-in handler, present the native Google sheet, extract the ID token, and pass it to the existing `AuthService.signInWithGoogle(idToken:)` which already hits Supabase's `/auth/v1/token?grant_type=id_token` endpoint.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, Swift Package Manager, GoogleSignIn-iOS SDK.

**Testing note:** Per the design doc (`docs/superpowers/specs/2026-04-20-google-signin-design.md`), this work has **no unit tests** — the OAuth flow is UI-bound and SDK-mediated, so mocking `GIDSignIn` would only test the mock. Verification is by build success and a manual device test plan at the end of this plan. Tasks therefore use a "make change → build → verify" rhythm rather than TDD.

**Prerequisites (user has confirmed complete):**
- Google Cloud Console iOS OAuth 2.0 client exists with bundle ID `com.rohanthomas.PokerStats`.
- Google Cloud Console Web OAuth 2.0 client exists.
- Supabase Auth → Providers → Google enabled with the **Web** client ID + secret.
- `GOOGLE_CLIENT_ID` in `.env` is populated with the **iOS** client ID.

---

## File Structure

**Files created:**
- `PokerStats/Info.plist` — explicit Info.plist for the app target; replaces all `INFOPLIST_KEY_*` build settings and adds `CFBundleURLTypes`.

**Files modified:**
- `project.yml` — add SPM dependency on `GoogleSignIn-iOS`; switch `PokerStats` target to use the explicit `Info.plist`; remove all `INFOPLIST_KEY_*` lines and `GENERATE_INFOPLIST_FILE`/`INFOPLIST_GENERATION_MODE`.
- `PokerStats/App/PokerStatsApp.swift` — import `GoogleSignIn`; configure `GIDSignIn.sharedInstance.configuration` in `init()`; add `.onOpenURL` handler.
- `PokerStats/ViewModels/AuthViewModel.swift` — replace stub `handleGoogleSignIn()` with real implementation.
- `PokerStats/Services/Auth/AuthService.swift` — import `GoogleSignIn`; call `GIDSignIn.sharedInstance.signOut()` from `signOut()`.
- `README.md` — update "Zero dependencies" claims to reflect the one added dependency.

**Files NOT touched:**
- `PokerStats/Services/Cloud/Secrets.swift` — `googleClientID` already exists at lines 23-25.
- `PokerStats/Services/Cloud/SupabaseClient.swift` — `signInWithIdToken(provider: .google, ...)` already works.
- `PokerStats/Services/Auth/AuthService.swift:signInWithGoogle` — already works, only `signOut` is modified.
- `PokerStats/Views/Auth/SignInView.swift` — the Google button at lines 105-119 already calls `authViewModel.handleGoogleSignIn()`; no view changes needed.

---

## Task 1: Add GoogleSignIn-iOS SPM dependency

**Files:**
- Modify: `project.yml` (add `packages:` block and reference from `PokerStats` target's `dependencies:`)

- [ ] **Step 1: Add `packages:` top-level block to `project.yml`**

Add after the `schemes:` block (before `targets:`), anchored just below the `archive: config: Release` line of the `PokerStats` scheme:

```yaml
packages:
  GoogleSignIn:
    url: https://github.com/google/GoogleSignIn-iOS
    from: 7.1.0
```

- [ ] **Step 2: Add package product to the `PokerStats` target's `dependencies:`**

Locate `project.yml` line 90-91:

```yaml
    dependencies:
      - target: PokerStatsWidgets
```

Replace with:

```yaml
    dependencies:
      - target: PokerStatsWidgets
      - package: GoogleSignIn
        product: GoogleSignIn
      - package: GoogleSignIn
        product: GoogleSignInSwift
```

(Both products are needed: `GoogleSignIn` for `GIDSignIn`/`GIDConfiguration`; `GoogleSignInSwift` for the SwiftUI-flavored helpers — we don't use those directly but the package requires the companion product on some versions; safe to include.)

- [ ] **Step 3: Regenerate the Xcode project**

Run from repo root:

```bash
xcodegen generate
```

Expected output: `Loaded project` followed by `Created project at ...PokerStats.xcodeproj`. No errors.

- [ ] **Step 4: Resolve packages**

Run:

```bash
xcodebuild -resolvePackageDependencies -project PokerStats.xcodeproj -scheme PokerStats
```

Expected: package graph resolves successfully with `GoogleSignIn-iOS` and its transitive deps (`AppAuth`, `GTMAppAuth`, `GTMSessionFetcher`). No errors.

- [ ] **Step 5: Build to confirm nothing is broken yet**

```bash
xcodebuild build -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: `BUILD SUCCEEDED`. (The SDK is linked but unused so far — this just proves the dependency resolves and compiles.)

- [ ] **Step 6: Commit**

```bash
git add project.yml PokerStats.xcodeproj
git commit -m "build: add GoogleSignIn-iOS SPM dependency

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

(Note: `PokerStats.xcodeproj` is regenerated; confirm whether your repo tracks it. If `.gitignore` excludes it, only `project.yml` will stage — that's fine.)

---

## Task 2: Create explicit Info.plist with URL scheme

**Files:**
- Create: `PokerStats/Info.plist`

**Context:** The Google OAuth callback lands at a URL of the form `com.googleusercontent.apps.<digits>-<hash>://...`. iOS routes that back to our app only if the scheme is declared in `CFBundleURLTypes`. This key is an array of dictionaries, which can't be set via the `INFOPLIST_KEY_*` shortcut — so we have to move to an explicit Info.plist. All the current `INFOPLIST_KEY_*` lines on the `PokerStats` target must be ported over so we don't lose orientation/launch-screen/Live-Activities behavior.

- [ ] **Step 1: Find the reversed-client-ID**

The reversed client ID is the iOS OAuth client ID with its components reversed and the `.apps.googleusercontent.com` suffix moved to the front as `com.googleusercontent.apps.`. E.g. if the iOS client ID is `123456789-abcdef.apps.googleusercontent.com`, the reversed form is `com.googleusercontent.apps.123456789-abcdef`.

Find it in Google Cloud Console → APIs & Services → Credentials → click your iOS OAuth client → the "iOS URL scheme" field shows this value directly. Save it; you'll paste it below as `<REVERSED_CLIENT_ID>`.

- [ ] **Step 2: Create `PokerStats/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIRequiresFullScreen</key>
	<false/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
	</array>
	<key>NSSupportsLiveActivities</key>
	<true/>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>com.rohanthomas.PokerStats.google-oauth</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string><REVERSED_CLIENT_ID></string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

Replace `<REVERSED_CLIENT_ID>` with the actual value from Step 1.

- [ ] **Step 3: Commit**

```bash
git add PokerStats/Info.plist
git commit -m "build: add explicit Info.plist for PokerStats target

Required to declare the Google OAuth callback URL scheme, which can't
be expressed via INFOPLIST_KEY_* build settings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Switch `PokerStats` target to use explicit Info.plist

**Files:**
- Modify: `project.yml:90-113` (the `PokerStats` target's `dependencies:` and `settings.base:` blocks)

- [ ] **Step 1: Read current `PokerStats` target settings**

Current state in `project.yml` (lines 90-113):

```yaml
    dependencies:
      - target: PokerStatsWidgets
      - package: GoogleSignIn
        product: GoogleSignIn
      - package: GoogleSignIn
        product: GoogleSignInSwift
    settings:
      base:
        INFOPLIST_GENERATION_MODE: GeneratedFile
        PRODUCT_BUNDLE_IDENTIFIER: com.rohanthomas.PokerStats
        PRODUCT_NAME: PokerStats
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "2"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
        SWIFT_EMIT_LOC_STRINGS: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortraitUpsideDown"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortraitUpsideDown"
        INFOPLIST_KEY_UIRequiresFullScreen: false
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"
        TARGETED_DEVICE_FAMILY: "1"
        SUPPORTS_MACCATALYST: NO
        SWIFT_STRICT_CONCURRENCY: complete
        SUPPORTS_LIVE_ACTIVITIES: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
```

- [ ] **Step 2: Add `info:` block after `dependencies:` and remove `INFOPLIST_KEY_*` / `INFOPLIST_GENERATION_MODE` / `GENERATE_INFOPLIST_FILE`**

Change that section to:

```yaml
    dependencies:
      - target: PokerStatsWidgets
      - package: GoogleSignIn
        product: GoogleSignIn
      - package: GoogleSignIn
        product: GoogleSignInSwift
    info:
      path: PokerStats/Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.rohanthomas.PokerStats
        PRODUCT_NAME: PokerStats
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "2"
        SWIFT_EMIT_LOC_STRINGS: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"
        TARGETED_DEVICE_FAMILY: "1"
        SUPPORTS_MACCATALYST: NO
        SWIFT_STRICT_CONCURRENCY: complete
        SUPPORTS_LIVE_ACTIVITIES: YES
```

Removed keys (all now expressed in `PokerStats/Info.plist`): `INFOPLIST_GENERATION_MODE`, `GENERATE_INFOPLIST_FILE`, `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`, `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`, `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`, `INFOPLIST_KEY_UIRequiresFullScreen`, `INFOPLIST_KEY_UILaunchScreen_Generation`.

- [ ] **Step 3: Regenerate Xcode project**

```bash
xcodegen generate
```

Expected: no errors.

- [ ] **Step 4: Build and verify all Info.plist values carried over**

```bash
xcodebuild build -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Inspect the built app's Info.plist**

```bash
BUILT_PLIST=$(find ~/Library/Developer/Xcode/DerivedData -name "Info.plist" -path "*PokerStats.app/*" 2>/dev/null | head -1)
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$BUILT_PLIST"
/usr/libexec/PlistBuddy -c "Print :UISupportedInterfaceOrientations" "$BUILT_PLIST"
/usr/libexec/PlistBuddy -c "Print :NSSupportsLiveActivities" "$BUILT_PLIST"
/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$BUILT_PLIST"
```

Expected output: `CFBundleURLTypes` contains the `com.googleusercontent.apps.*` scheme; orientations array contains all four; `NSSupportsLiveActivities` is `true`; `ITSAppUsesNonExemptEncryption` is `false`.

- [ ] **Step 6: Commit**

```bash
git add project.yml
git commit -m "build: switch PokerStats target to explicit Info.plist

Migrated all INFOPLIST_KEY_* build settings into PokerStats/Info.plist
to support CFBundleURLTypes (required for Google OAuth callback scheme).
No behavioral change expected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Configure GIDSignIn at app launch

**Files:**
- Modify: `PokerStats/App/PokerStatsApp.swift`

- [ ] **Step 1: Add `import GoogleSignIn` and configure the SDK**

Modify `PokerStats/App/PokerStatsApp.swift`. Current imports (lines 1-2):

```swift
import SwiftUI
import SwiftData
```

Change to:

```swift
import SwiftUI
import SwiftData
import GoogleSignIn
```

- [ ] **Step 2: Configure `GIDSignIn` in `init()`**

Current `init()` (lines 10-16):

```swift
    init() {
        do {
            container = try AppGroupContainer.createSharedModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
```

Change to:

```swift
    init() {
        do {
            container = try AppGroupContainer.createSharedModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Secrets.googleClientID)
    }
```

- [ ] **Step 3: Add `.onOpenURL` handler to route OAuth callback**

Current `body` modifier chain on `ContentView()` (lines 20-55). The existing chain ends with `.onChange(of: authService.isAuthenticated)`. Add a new `.onOpenURL` modifier after `.onAppear` and before `.onChange`.

Find (lines 46-55):

```swift
                .onAppear {
                    if !ProcessInfo.processInfo.arguments.contains("--seed-screenshot-data") {
                        authService.initialize()
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        autoRestoreIfEmpty()
                    }
                }
```

Change to:

```swift
                .onAppear {
                    if !ProcessInfo.processInfo.arguments.contains("--seed-screenshot-data") {
                        authService.initialize()
                    }
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        autoRestoreIfEmpty()
                    }
                }
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PokerStats/App/PokerStatsApp.swift
git commit -m "feat(auth): configure GoogleSignIn SDK at launch

Initialize GIDSignIn with the iOS client ID from Secrets.plist and
route OAuth callback URLs via .onOpenURL.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Implement real Google Sign-In flow in AuthViewModel

**Files:**
- Modify: `PokerStats/ViewModels/AuthViewModel.swift`

- [ ] **Step 1: Add `GoogleSignIn` and `UIKit` imports**

Current imports (lines 1-2):

```swift
import Foundation
import AuthenticationServices
```

Change to:

```swift
import Foundation
import AuthenticationServices
import GoogleSignIn
import UIKit
```

- [ ] **Step 2: Replace the `handleGoogleSignIn()` stub**

Current stub (lines 91-96):

```swift
    // MARK: - Google Sign In (placeholder — requires GoogleSignIn SDK)

    func handleGoogleSignIn() {
        // TODO: Integrate GoogleSignIn SDK
        errorMessage = "Google Sign-In is not yet configured."
    }
```

Replace with:

```swift
    // MARK: - Google Sign In

    func handleGoogleSignIn() {
        guard let rootVC = Self.topPresentingViewController() else {
            errorMessage = "Unable to present Google Sign-In."
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
                guard let idToken = result.user.idToken?.tokenString else {
                    throw AuthServiceError.googleSignInFailed("No ID token returned")
                }
                try await authService.signInWithGoogle(idToken: idToken)
                isShowingSignIn = false
            } catch let error as GIDSignInError where error.code == .canceled {
                // User cancelled — silent no-op
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private static func topPresentingViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = keyWindow.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
```

Notes:
- The `topPresentingViewController` walks the presentation stack because `SignInView` is already presented as a sheet from `SettingsView`; the Google sheet must be presented from the top of the stack, not the root.
- `GIDSignInError.code == .canceled` is caught silently, matching the Apple cancellation pattern (`AuthViewModel.swift:52-53`).

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PokerStats/ViewModels/AuthViewModel.swift
git commit -m "feat(auth): implement Google Sign-In via GIDSignIn SDK

Presents the native Google sheet from the topmost presented VC,
extracts the ID token, and passes it to AuthService.signInWithGoogle
which already exchanges it for a Supabase session.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Clear GoogleSignIn state on sign-out

**Files:**
- Modify: `PokerStats/Services/Auth/AuthService.swift`

- [ ] **Step 1: Add `GoogleSignIn` import**

Current imports (lines 1-3):

```swift
import Foundation
import AuthenticationServices
import SwiftData
```

Change to:

```swift
import Foundation
import AuthenticationServices
import SwiftData
import GoogleSignIn
```

- [ ] **Step 2: Add `GIDSignIn.sharedInstance.signOut()` to `signOut()`**

Current `signOut()` (lines 148-159):

```swift
    func signOut() async {
        // Best-effort server sign out
        if let token = KeychainHelper.read(.accessToken) {
            try? await client.signOut(accessToken: token)
        }

        KeychainHelper.deleteAll()
        isAuthenticated = false
        userEmail = nil
        userId = nil
        error = nil
    }
```

Change to:

```swift
    func signOut() async {
        // Best-effort server sign out
        if let token = KeychainHelper.read(.accessToken) {
            try? await client.signOut(accessToken: token)
        }

        GIDSignIn.sharedInstance.signOut()

        KeychainHelper.deleteAll()
        isAuthenticated = false
        userEmail = nil
        userId = nil
        error = nil
    }
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PokerStats/Services/Auth/AuthService.swift
git commit -m "fix(auth): clear GoogleSignIn cached identity on sign-out

Prevents stale Google session state from surviving a user-initiated
sign-out.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Update README to reflect added dependency

**Files:**
- Modify: `README.md`

**Context:** `README.md` currently has three separate "zero dependencies" claims (badge at line 12, Tech Stack table row at line 115, Contributing bullet at line 380). All three need to be updated to be honest about the GoogleSignIn SDK, since App Review can fact-check binary contents against marketing claims.

- [ ] **Step 1: Update the badge (line 12)**

Find:

```markdown
  <img src="https://img.shields.io/badge/dependencies-zero-brightgreen?style=flat-square" alt="Dependencies">
```

Replace with:

```markdown
  <img src="https://img.shields.io/badge/dependencies-1%20(GoogleSignIn)-green?style=flat-square" alt="Dependencies">
```

- [ ] **Step 2: Update the Tech Stack table (line 115)**

Find:

```markdown
| **Dependencies** | Zero | Fully native, no third-party libraries |
```

Replace with:

```markdown
| **Dependencies** | GoogleSignIn-iOS only | Required for Google sign-in; no analytics, ads, or tracking SDKs |
```

- [ ] **Step 3: Update the Contributing section (line 380)**

Find:

```markdown
- Zero third-party dependencies policy
```

Replace with:

```markdown
- Minimal dependencies: only GoogleSignIn-iOS is permitted; no analytics, ads, or tracking SDKs
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update dependency claims in README

GoogleSignIn-iOS is now a dependency for the Google sign-in path.
Keeps the README honest for App Review fact-checking.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Manual device verification (cannot be automated)

**Files:** none — this is an on-device test.

**Context:** OAuth cannot be unit-tested meaningfully. Before merging or resubmitting to App Review, perform this on a physical iPhone signed into the developer account associated with the Google Cloud project.

- [ ] **Step 1: Install the build on a physical device**

Plug in an iPhone, select it as the destination in Xcode, press Cmd+R.

- [ ] **Step 2: Test the golden-path Google sign-in**

1. Settings tab → "Sign In" → SignInView appears.
2. Tap "Sign in with Google".
3. **Expected:** Native Google sheet slides up. Safari-based consent does *not* appear (it would if the iOS client ID or reversed-URL scheme is wrong).
4. Complete sign-in with a test Google account.
5. **Expected:** Sheet dismisses; app returns to Settings; Account section shows the signed-in email; "Cloud Backup" NavigationLink now enabled.

- [ ] **Step 3: Test backup works**

1. Navigate to Cloud Backup → tap "Back Up Now".
2. **Expected:** "Backed up N sessions" toast appears at top of screen (`PokerStatsApp.swift:33-42`).

- [ ] **Step 4: Test sign-out clears Google state**

1. Back in Settings → tap "Sign Out".
2. Tap "Sign In" → "Sign in with Google".
3. **Expected:** Google sheet prompts for account selection (does *not* silently re-auth with the previous account). If it silently re-auths, `GIDSignIn.sharedInstance.signOut()` did not run — check `AuthService.signOut()`.

- [ ] **Step 5: Test cancellation is silent**

1. Tap "Sign in with Google" → dismiss the sheet without completing.
2. **Expected:** No red error text appears. `errorMessage` stays nil.

- [ ] **Step 6: Regression — Apple Sign In still works**

1. Sign in with Apple → complete flow.
2. **Expected:** Signed in successfully, email shows in Settings (or "Hide My Email" proxy).

- [ ] **Step 7: Regression — email/password still works**

1. Sign out. Sign in with email/password using an existing Supabase user.
2. **Expected:** Signed in successfully.

- [ ] **Step 8: Regression — Delete Account still works**

1. While signed in, Settings → Delete Account → confirm twice.
2. **Expected:** Account deleted; app shows signed-out state; attempting to sign in with the deleted user's credentials fails.

- [ ] **Step 9: Document results**

Record pass/fail for each sub-step above. If any fail, file as follow-up tasks before the App Store resubmission.

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Add `GoogleSignIn-iOS` via SPM | Task 1 |
| Switch to explicit Info.plist with URL types | Tasks 2 + 3 |
| Load `googleClientID` from `Secrets.plist` | Already exists — noted in File Structure |
| Configure `GIDSignIn` in `PokerStatsApp.init()` | Task 4 |
| `.onOpenURL` handler on ContentView | Task 4 |
| Replace `handleGoogleSignIn()` stub | Task 5 |
| Silent cancellation, error propagation | Task 5 |
| `GIDSignIn.signOut()` from `AuthService.signOut()` | Task 6 |
| README honesty about dependency | Task 7 |
| Manual device test plan | Task 8 |

All spec items covered.

**Placeholder scan:** one intentional `<REVERSED_CLIENT_ID>` token in Task 2 Step 2 — explicitly flagged to be replaced with the user's actual value from Google Cloud Console (the plan cannot know this — it's a secret pulled from the user's GCP account). Every other step contains complete, runnable content.

**Type consistency:** `handleGoogleSignIn`, `AuthService.signInWithGoogle(idToken:)`, `GIDSignIn.sharedInstance`, `Secrets.googleClientID` used consistently across Tasks 4-6. `AuthServiceError.googleSignInFailed(_:)` is the existing case at `AuthService.swift:270`; reused in Task 5 for the "No ID token returned" path.
