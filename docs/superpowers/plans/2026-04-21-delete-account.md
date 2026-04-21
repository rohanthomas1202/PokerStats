# Delete Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Delete Account" actually delete the user's Supabase account and all cloud+local data, serialized correctly, with visible error feedback on failure.

**Architecture:** Single entry point `AuthService.deleteAccount(modelContext:)` orchestrates a strictly-serial pipeline: cloud delete via existing Edge Function → Keychain wipe → local SwiftData wipe → in-memory auth state reset. Failures at step 1 abort the pipeline so local data is preserved. The SettingsView binds a new error alert to `AuthViewModel.errorMessage` so failures surface to the user.

**Tech Stack:** Swift 6, SwiftUI, SwiftData (`@Model`: `Hand`, `Session`, `Settings`), Swift Testing (`@Test`/`#expect`), Supabase Edge Functions (Deno).

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `PokerStats/Services/Auth/LocalDataEraser.swift` | Pure function that deletes all user-owned SwiftData rows | **Create** |
| `PokerStatsTests/LocalDataEraserTests.swift` | Unit tests for the eraser | **Create** |
| `PokerStats/Services/Auth/AuthService.swift` | `deleteAccount` takes `ModelContext`, runs ordered pipeline | **Modify** |
| `PokerStats/ViewModels/AuthViewModel.swift` | `deleteAccount` takes `ModelContext`, populates `errorMessage` on throw | **Modify** |
| `PokerStats/Views/Settings/SettingsView.swift` | Final alert calls single method; adds error-alert binding | **Modify** |

The eraser lives next to `AuthService.swift` because it is only meaningful during account teardown. It is kept as a plain `enum` with a `static func` (no state, no init) so it is trivially testable against an in-memory `ModelContainer`.

---

## Prerequisite (Manual — outside the code tasks)

Before any code ships, the `delete-account` Edge Function must exist on the Supabase project the app actually uses (`bplrxbatvglxreulodtj`). Today it is likely deployed to `xukhlkjjrrwmorxtlizh` (per `supabase/.temp/project-ref`), which is wrong.

- [ ] **Prereq: Relink Supabase CLI and deploy the function**

Run (will prompt for interactive login to Supabase in a browser):

```bash
supabase link --project-ref bplrxbatvglxreulodtj
supabase functions deploy delete-account
```

Then, in the Supabase Dashboard for project `bplrxbatvglxreulodtj`:
1. Go to **Edge Functions** → confirm `delete-account` is listed and enabled.
2. No secrets to set manually — `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` are auto-injected for Edge Functions on Supabase's platform.

Verify with a dry call (should return 401 because no auth header, not 404):

```bash
curl -i -X POST "https://bplrxbatvglxreulodtj.supabase.co/functions/v1/delete-account"
```

Expected: `HTTP/2 401` and JSON body `{"error":"Missing authorization"}`. If you see `404`, the deploy did not land — redo the deploy step.

---

## Task 1: Create a pure local-data eraser (TDD)

**Files:**
- Create: `PokerStats/Services/Auth/LocalDataEraser.swift`
- Create: `PokerStatsTests/LocalDataEraserTests.swift`

The eraser is pure: it takes a `ModelContext`, deletes every row of `Hand`, `Session`, `Settings`, saves, and returns. No network. No keychain. No singletons. That makes it testable against an in-memory `ModelContainer` using the existing `TestHelpers.createContainer()`.

- [ ] **Step 1.1: Write the failing test file**

Create `PokerStatsTests/LocalDataEraserTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import PokerStats

@Suite("LocalDataEraser Tests")
struct LocalDataEraserTests {

    @MainActor
    @Test func eraseAll_removesAllSessionsHandsAndSettings() throws {
        let container = try TestHelpers.createContainer()
        let context = ModelContext(container)

        let hand = TestHelpers.foldHand()
        let session = TestHelpers.completedSession(hands: [hand])
        context.insert(session)

        let settings = Settings()
        context.insert(settings)

        try context.save()

        // Sanity: container is non-empty
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Hand>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Settings>()) == 1)

        try LocalDataEraser.eraseAll(in: context)

        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Hand>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Settings>()) == 0)
    }

    @MainActor
    @Test func eraseAll_onEmptyContainer_succeeds() throws {
        let container = try TestHelpers.createContainer()
        let context = ModelContext(container)

        try LocalDataEraser.eraseAll(in: context)

        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
    }
}
```

- [ ] **Step 1.2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PokerStatsTests/LocalDataEraserTests 2>&1 | tail -30
```

Expected: build fails with "Cannot find 'LocalDataEraser' in scope" (or similar). If the build compiles, the test file wasn't added to the test target — re-run `xcodegen generate` first (xcodegen uses folder references, so new files under `PokerStatsTests/` are picked up automatically; if not, check that the target's `sources` in `project.yml` includes the path).

- [ ] **Step 1.3: Implement `LocalDataEraser`**

Create `PokerStats/Services/Auth/LocalDataEraser.swift`:

```swift
import Foundation
import SwiftData

/// Deletes all user-owned SwiftData rows from the given context.
///
/// This is the local half of "delete my account" — it wipes every row of every
/// @Model type that represents user data. It does not touch the Keychain, does
/// not call the network, and is safe to call on an empty container.
enum LocalDataEraser {

    @MainActor
    static func eraseAll(in context: ModelContext) throws {
        try context.delete(model: Hand.self)
        try context.delete(model: Session.self)
        try context.delete(model: Settings.self)
        try context.save()
    }
}
```

- [ ] **Step 1.4: Regenerate Xcode project**

New `.swift` files under `PokerStats/` and `PokerStatsTests/` are picked up automatically because `project.yml` uses folder sources, but regenerate to be certain:

```bash
xcodegen generate
```

- [ ] **Step 1.5: Run the test to verify it passes**

Run:

```bash
xcodebuild test -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PokerStatsTests/LocalDataEraserTests 2>&1 | tail -30
```

Expected: both tests pass.

- [ ] **Step 1.6: Commit**

```bash
git add PokerStats/Services/Auth/LocalDataEraser.swift PokerStatsTests/LocalDataEraserTests.swift PokerStats.xcodeproj/project.pbxproj
git commit -m "feat(auth): add LocalDataEraser for full account wipe"
```

---

## Task 2: Refactor `AuthService.deleteAccount` to orchestrate the serial pipeline

**Files:**
- Modify: `PokerStats/Services/Auth/AuthService.swift:183-208`

The method changes signature to accept a `ModelContext`, and its body becomes: cloud delete → keychain wipe → `LocalDataEraser.eraseAll` → in-memory state reset → widget reload. If the cloud call throws, the method re-throws immediately — nothing else runs.

- [ ] **Step 2.1: Replace the existing `deleteAccount` implementation**

In `PokerStats/Services/Auth/AuthService.swift`, replace the current `deleteAccount()` method (lines 185–208) with:

```swift
func deleteAccount(modelContext: ModelContext) async throws {
    isLoading = true
    error = nil

    do {
        // 1. Delete cloud data + auth user via Edge Function. If this throws,
        //    local data stays intact so the user can retry.
        try await client.callEdgeFunction("delete-account")

        // 2. Clear auth state from Keychain.
        KeychainHelper.deleteAll()

        // 3. Wipe local SwiftData. Swallow errors here: the server account is
        //    already gone, so the user must be treated as signed out regardless.
        do {
            try LocalDataEraser.eraseAll(in: modelContext)
        } catch {
            // Intentionally ignored; server is source of truth at this point.
        }

        // 4. Reset in-memory state and widgets.
        isAuthenticated = false
        userEmail = nil
        userId = nil
        isLoading = false

        WidgetCenter.shared.reloadAllTimelines()
    } catch {
        isLoading = false
        let authError = AuthServiceError.deletionFailed(error.localizedDescription)
        self.error = authError
        throw authError
    }
}
```

- [ ] **Step 2.2: Add the WidgetKit import if missing**

Check the top of `PokerStats/Services/Auth/AuthService.swift`. The existing imports are `Foundation`, `AuthenticationServices`, `SwiftData`. Add `WidgetKit` if it isn't already there:

```swift
import Foundation
import AuthenticationServices
import SwiftData
import WidgetKit
```

- [ ] **Step 2.3: Build to verify compile**

Run:

```bash
xcodebuild -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. If you see "Cannot find 'ModelContext'" the `SwiftData` import is missing. If "Cannot find 'WidgetCenter'" the `WidgetKit` import is missing.

- [ ] **Step 2.4: Commit**

```bash
git add PokerStats/Services/Auth/AuthService.swift
git commit -m "refactor(auth): serialize deleteAccount pipeline, wipe local data"
```

---

## Task 3: Propagate `ModelContext` through `AuthViewModel`

**Files:**
- Modify: `PokerStats/ViewModels/AuthViewModel.swift:107-124`

The view model now takes the context and forwards it. Error handling stays the same (populate `errorMessage`), but now an error means "cloud delete failed, nothing else happened" — which is exactly what the user needs to see.

- [ ] **Step 3.1: Update the method signature and body**

Replace the `deleteAccount()` method in `PokerStats/ViewModels/AuthViewModel.swift` with:

```swift
func deleteAccount(modelContext: ModelContext) {
    isProcessing = true
    errorMessage = nil

    Task {
        do {
            try await authService.deleteAccount(modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}
```

- [ ] **Step 3.2: Add the SwiftData import**

At the top of `PokerStats/ViewModels/AuthViewModel.swift`, the existing imports are `Foundation`, `AuthenticationServices`. Add `SwiftData`:

```swift
import Foundation
import AuthenticationServices
import SwiftData
```

- [ ] **Step 3.3: Build to verify compile**

Run:

```bash
xcodebuild -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20
```

Expected: build fails in `SettingsView.swift` with "Missing argument for parameter 'modelContext'" on the call site. That's exactly what the next task fixes — good.

- [ ] **Step 3.4: Commit**

```bash
git add PokerStats/ViewModels/AuthViewModel.swift
git commit -m "refactor(auth): thread ModelContext through AuthViewModel.deleteAccount"
```

---

## Task 4: Wire SettingsView to the new method and add the error alert

**Files:**
- Modify: `PokerStats/Views/Settings/SettingsView.swift:182-190` (final alert)
- Modify: `PokerStats/Views/Settings/SettingsView.swift` (new error alert)

Two changes to SettingsView:
1. Final alert's destructive button becomes a single call to `authViewModel?.deleteAccount(modelContext: modelContext)`. The old concurrent `viewModel.deleteAllData(...)` call is removed (`LocalDataEraser` now owns that, and it only runs after a successful server delete).
2. A new `.alert` appears iff `authViewModel?.errorMessage` is non-nil. OK dismisses by clearing `errorMessage`.

- [ ] **Step 4.1: Update the final destructive alert's action**

In `PokerStats/Views/Settings/SettingsView.swift`, find the alert at line 182 (`.alert("This cannot be undone.", …)`). Replace its action block. Before:

```swift
.alert("This cannot be undone.", isPresented: $isShowingDeleteAccountFinal) {
    Button("Cancel", role: .cancel) { }
    Button("Yes, Delete My Account", role: .destructive) {
        authViewModel?.deleteAccount()
        viewModel.deleteAllData(from: modelContext)
    }
} message: {
    Text("Your account, all cloud backups, and all local data will be permanently deleted.")
}
```

After:

```swift
.alert("This cannot be undone.", isPresented: $isShowingDeleteAccountFinal) {
    Button("Cancel", role: .cancel) { }
    Button("Yes, Delete My Account", role: .destructive) {
        authViewModel?.deleteAccount(modelContext: modelContext)
    }
} message: {
    Text("Your account, all cloud backups, and all local data will be permanently deleted.")
}
```

- [ ] **Step 4.2: Add the error alert**

Add a new `.alert` modifier to the `Form` — place it right after the `.alert("This cannot be undone.", …)` modifier from Step 4.1. Insert:

```swift
.alert(
    "Couldn't delete account",
    isPresented: Binding(
        get: { authViewModel?.errorMessage != nil },
        set: { newValue in
            if !newValue { authViewModel?.errorMessage = nil }
        }
    )
) {
    Button("OK", role: .cancel) { }
} message: {
    Text(authViewModel?.errorMessage ?? "")
}
```

This alert fires whenever `errorMessage` goes non-nil, and clears it on OK so the same error can be shown again if the user retries and fails again.

- [ ] **Step 4.3: Build to verify compile**

Run:

```bash
xcodebuild -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 15' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4.4: Run the full test suite**

Run:

```bash
xcodebuild test -project PokerStats.xcodeproj -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -30
```

Expected: all tests pass (new `LocalDataEraserTests` + all pre-existing suites).

- [ ] **Step 4.5: Commit**

```bash
git add PokerStats/Views/Settings/SettingsView.swift
git commit -m "feat(settings): single-call delete account with error alert"
```

---

## Task 5: Manual verification in the simulator

Automated tests cover the local-wipe mechanics. The network and UX flows have to be checked by hand because the Supabase client is a singleton and the flow is UI-bound.

- [ ] **Step 5.1: Happy path**

1. Run the app in the simulator against the real Supabase backend (`bplrxbatvglxreulodtj`).
2. Sign in with a test account (Apple, Google, or email — any provider).
3. Record a session with at least one hand.
4. Settings → Delete Account → "Delete Account" → "Yes, Delete My Account".
5. Expected:
   - Returning to Sessions shows an empty list.
   - Returning to Settings shows the signed-out state ("Sign In" button visible; no "Delete Account" button).
   - In the Supabase Dashboard for `bplrxbatvglxreulodtj`: Authentication → Users no longer lists this user; Database → `profiles` has no row for that user ID; Storage → `backups` bucket has no `<userId>/…` files.

- [ ] **Step 5.2: Cloud-failure path**

1. Sign in fresh, record a session.
2. Before tapping Delete: in the Supabase Dashboard, disable the `delete-account` Edge Function (Edge Functions → delete-account → toggle off). This causes the call to fail.
3. Run the delete flow.
4. Expected:
   - Error alert "Couldn't delete account" appears with a non-empty message.
   - Sessions list is unchanged — local data was not wiped.
   - User remains signed in (Delete Account button still visible in Settings).
5. Re-enable the Edge Function when done.

- [ ] **Step 5.3: Offline path**

1. Sign in fresh, record a session.
2. Enable Airplane Mode in the simulator (Settings app → Airplane Mode), or use the Network Link Conditioner's "100% Loss" profile.
3. Run the delete flow.
4. Expected: error alert with a network-failure message, local data intact, still signed in.

---

## Self-Review Checklist

- **Spec coverage:**
  - "Cloud delete → Keychain → local wipe → in-memory state" → Task 2 ✓
  - "Errors surfaced via alert" → Task 4 Step 4.2 ✓
  - "Widen local wipe to `Hand`/`Session`/`Settings`" → Task 1 Step 1.3 ✓
  - "Serial ordering, abort on cloud failure" → Task 2 Step 2.1 (`try await` on first line, re-throw on catch) ✓
  - "Edge Function deployed to correct project" → Prereq section ✓
  - "Non-goals: Apple revocation, toast, new alerts" → not added anywhere ✓
  - "Tests: happy / cloud-fail / offline" → Task 5 ✓
- **Placeholders:** none — every code step shows full replacement text.
- **Type consistency:** `deleteAccount(modelContext:)` used consistently across AuthService, AuthViewModel, SettingsView call site. `LocalDataEraser.eraseAll(in:)` used consistently.
- **No references to undefined symbols:** `TestHelpers.createContainer()`, `foldHand()`, `completedSession(hands:)`, `Settings()` all verified to exist in `PokerStatsTests/TestHelpers.swift` and `PokerStats/Models/`.
