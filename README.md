<h1 align="center">PokerStats</h1>

<p align="center">
  <strong>A native iOS app for live poker players to track sessions, log hands in real-time, and compute HUD-style statistics offline, with optional Sign in with Apple and Supabase cloud backup.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2026%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/swiftui-latest-purple?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/swiftdata-latest-green?style=flat-square" alt="SwiftData">
  <img src="https://img.shields.io/badge/iOS%20unit%20tests-459%20passing-success?style=flat-square" alt="459 iOS unit tests passing">
</p>

---

## The Problem

Live poker players have no fast, mobile-first tool to track both financial results **and** playing tendencies. Existing apps are either money-only trackers (no hand data) or full hand-history tools designed for online poker (unusable at a live table). Without data, players can't identify leaks in their game.

## The Solution

PokerStats combines session-level financial tracking with hand logging designed for live play. The sub-3-second entry target guides the interaction; it is not a measured timing guarantee. The app computes **VPIP, PFR, Fold to 3-Bet%, C-Bet%, WTSD%, W$SD%** from recorded hands. Session tracking and analysis work offline; sign-in enables cloud backup and restore.

---

## Features

### Session Management
- **Session setup** with buy-in, stakes, location, and optional table configuration
- **Live session timer** computed from persisted start time
- **Rebuy and add-on tracking** during active sessions
- **Cash-out and P&L auto-calculation** at session end
- **Session recovery** — kill the app mid-session and pick up right where you left off

### Hand Logger
The hand logger uses progressive disclosure. Tap **Log Hand** to open the sheet, select a position or Skip, then choose Fold, Call, or Raise. Fold saves the hand and dismisses the sheet. Calls ask for the result; raises also ask about facing a 3-bet, the response if needed, and a c-bet if the player saw the flop.

With manual position selection, a preflop fold takes two choices inside the sheet, plus the tap to open it. With calibrated automatic position tracking, the sheet starts at preflop, so Fold is one choice inside the sheet. It is not a one-tap action from the active session screen. Notes and position corrections are optional.

### Position Tracking
- Manual position selection, including Skip for unknown position
- Optional table setup and button calibration for automatic position rotation, with corrections during a session
- Per-position hand counts, VPIP, and PFR on the dashboard and session detail screen

### Poker Statistics Engine
All stats computed on-demand from raw hand data using pure functions:

| Stat | What It Measures |
|------|------------------|
| **VPIP** | % of hands voluntarily put money in preflop |
| **PFR** | % of hands raised preflop |
| **Fold to 3-Bet%** | When you raised and faced a 3-bet, how often you folded |
| **C-Bet%** | When you raised preflop and saw the flop, how often you bet |
| **WTSD%** | Of hands that saw the flop, how often you reached showdown |
| **W$SD%** | Of showdown hands, how often you won |
| **Hourly Rate** | Financial win rate per hour played |
| **Session ROI** | Return on investment per session |

### Dashboard
- Lifetime P&L with hourly rate, hours played, and session count
- **Play style radar chart** — Diamond chart with TAG/LAG/ROCK/FISH quadrant classification
- **2-column stat grid** with range bars and help icons for VPIP, PFR, C-Bet, WTSD
- **Circular fold frequency gauges** for preflop fold % and fold-to-3-bet %
- **Mental insights** — Calm vs Tilted hourly rate comparison
- **Leak Finder card** — Quick leak count and overall health rating with tap-through to full analysis
- Active session banner with live timer
- Recent sessions at a glance

### Trend Charts (Swift Charts)
- **Cumulative bankroll** line chart over time
- **Rolling VPIP/PFR** dual-line trend
- **Profit by day of week** bar chart (green/red)
- **Session P&L distribution** histogram
- Time filter: All Time, 30 days, 90 days, 6 months

### Tilt & Energy Tracker
- Self-report **tilt, energy, and focus** (1–5 scale) at session start and mid-session check-ins
- **Mental correlation analysis** — hourly rate broken down by mental state level
- Per-session mental state badges in session detail

### Live Activities & Widgets
- **Lock screen Live Activity** during active sessions with timer and hand count; location and invested amount are privacy-sensitive
- **Dynamic Island** support (compact and expanded)
- **Home screen widget** with lifetime P&L, sessions, and streak (small + medium sizes)

### Leak Finder & Coaching Insights
- **Automated stat analysis** comparing your play against optimal ranges
- **Two reference profiles** — Full Ring (9-max) and 6-Max cash games
- **Three-tier severity rating** — Healthy (green), Borderline (yellow), Leak (red)
- **Actionable suggestions** for each stat with specific strategic advice
- **Per-session insights** in session detail view (10+ hands required)
- **Overall health assessment** — Solid, Needs Work, or Leaking
- Minimum 20 hands required for lifetime analysis

### Account & Cloud Backup
- Optional **Sign in with Apple** through Supabase Auth, with Keychain session storage
- Manual backups and automatic backups after local changes while signed in
- Backup history, loading and retry states, and pull-to-refresh that keeps existing content visible
- Restore a selected backup, with an option to back up first; restore replaces local data rather than merging it
- Automatic restore into an empty local store after sign-in
- Account deletion with Apple reauthentication when required, cloud deletion, and local cleanup with retry if cleanup fails

Cloud backups use Supabase Storage with metadata in Postgres. They are encrypted on the server, not end-to-end encrypted. Backup and restore are available today; ongoing cross-device sync and sharing belong to milestone 1.1.

### Session History
- Full session list grouped by month
- Search by location or stakes
- Aggregate summary (total sessions, P&L, hours)
- Detailed session view with per-session stats, hand log, and session-specific leak insights

---

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Language** | Swift 6 | Strict concurrency |
| **UI** | SwiftUI | Native, declarative, mature on iOS 26 |
| **Persistence** | SwiftData | Modern replacement for Core Data, `@Model` + `@Query` |
| **Architecture** | MVVM | Lightweight, idiomatic SwiftUI with `@Observable` |
| **Testing** | Swift Testing | Modern `@Test` + `#expect` framework |
| **Dependencies** | Swift Package Manager | Third-party packages allowed; each one listed and pinned (see [Dependencies](#dependencies)) |

---

## Dependencies

Third-party Swift packages are allowed. Every package the app uses is listed here and pinned, so anyone working on the project (including the bot team) can see what changed when a build breaks.

### Swift packages (SPM)

| Name | Pinned version | Purpose | Link |
|------|----------------|---------|------|
| supabase-swift (products Auth, Functions, PostgREST, Storage) | 2.55.6 | Supabase clients: Sign in with Apple and the session (Keychain storage, token refresh), backups in Storage, `backup_metadata` and `profiles` through PostgREST, and the `delete-account` edge function. Realtime is not used. | [supabase/supabase-swift](https://github.com/supabase/supabase-swift) |

`Package.resolved` also pins the packages supabase-swift depends on (swift-asn1, swift-clocks, swift-concurrency-extras, swift-crypto, swift-http-types, swift-issue-reporting, xctest-dynamic-overlay). They are not used by the app directly.

### Policy

When a PR adds, removes, or updates a package, the same PR must:

1. Declare it in `project.yml` under `packages:`, pinned to an `exactVersion` or `upToNextMinor` range (no `upToNextMajor`, branch, or revision pins).
2. Add or update its row in the table above: name, the exact version from `Package.resolved`, purpose, and repo link.
3. Commit the updated `PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

The table must match `Package.resolved` exactly. The rest of `PokerStats.xcodeproj` is generated by XcodeGen and gitignored, except the shared scheme in `xcshareddata/xcschemes/` and this `Package.resolved`. `xcodegen generate` can delete that file, so if it disappears after regenerating, run `git restore PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. `ci_scripts/generate_project.sh` runs `xcodegen generate` and puts the committed file back; Xcode Cloud (`ci_post_clone.sh`) and the fastlane `beta` and `release` lanes use it. It fails if `Package.resolved` is missing, uncommitted or differs from the commit, and the lanes' `build_app` passes `disable_package_automatic_updates: true` (`-disableAutomaticPackageResolution`), so TestFlight and App Store builds use exactly the committed package versions or fail.

### Tooling (not shipped in the app)

- **XcodeGen**: generates the Xcode project from `project.yml`. Installed with Homebrew, unpinned.
- **fastlane**: screenshots and App Store uploads (`fastlane/`). There is no `Gemfile`, so the version is not pinned. The `release` lane only uploads the build and metadata (`submit_for_review: false`, `automatic_release: false`). Submitting for App Review is manual and owner-only, done in App Store Connect. `ios-release.yml` runs `fastlane ios beta` for `ios-sprint-*` tags and `fastlane ios release` for `ios-v*` tags (see Releases). Ordinary CI never calls either upload lane. The `beta` and `release` lanes set the build number (`CFBundleVersion`) to the UTC time as `YYYYMMDDHHMMSS` from `ci_scripts/build_number.sh`, passed as `CURRENT_PROJECT_VERSION` so the app and its extensions match, then check the archive with `ci_scripts/check_build_numbers.sh` before uploading. The export sets `manageAppVersionAndBuildNumber` to false, so the uploaded IPA keeps the checked build number. See Continuous Integration for why build numbers can't go back to a smaller counter. The `CURRENT_PROJECT_VERSION` in `project.yml` is only the local default.
- **Ajv 8.20.0** (`npm:ajv`): JSON Schema validator for the sync contract test in `shared/fixtures/sync/` (#233) and the stat fixture test in `shared/fixtures/stats/` (#235). Test-only, pinned in each folder's `deno.json` and locked in `deno.lock`; run in the "Shared fixtures" CI job.
- **Supabase edge function** (`supabase/functions/delete-account`): imports `@supabase/supabase-js@2.118.0` from esm.sh and `@supabase/functions-js@2.118.0` from JSR (`deno.json`), both pinned to exact versions. Apple token revocation uses WebCrypto and `fetch` only, with no extra package. It needs the Edge Function secrets `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID` and `APPLE_PRIVATE_KEY`. The owner steps to create the Apple key, set those secrets, deploy the function and check it are in [docs/runbooks/delete-account-deploy.md](docs/runbooks/delete-account-deploy.md).

---

## Requirements

- **Xcode 26.0** or later
- **iOS 26.0+** deployment target
- **XcodeGen** (for project generation from `project.yml`)

### Install XcodeGen

```bash
brew install xcodegen
```

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/rohanthomas1202/PokerStats.git
cd PokerStats
```

### 2. Generate the Xcode project

The Xcode project is generated from `project.yml` using XcodeGen. This keeps the project file out of source control and avoids merge conflicts.

```bash
./ci_scripts/generate_project.sh
```

The wrapper restores the committed `Package.resolved` after generation. See [Dependencies](#dependencies) for the lockfile policy. Cloud features also need Supabase configuration; the pre-build step in `project.yml` reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from a local, untracked `.env`. Without it, the build uses placeholders.

### 3. Open in Xcode

```bash
open PokerStats.xcodeproj
```

### 4. Select a simulator and run

1. In Xcode, select **iPhone 17 Pro** (or any iOS 26+ simulator) from the device dropdown
2. Press **Cmd + R** to build and run

### 5. Run tests

```bash
xcodebuild test \
  -scheme PokerStats \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Or in Xcode: **Cmd + U**

---

## Repo layout

One repo holds the iOS app, the backend, and the web app.

- **iOS app:** `PokerStats/`, `PokerStatsWidgets/`, `PokerStatsTests/`, and `PokerStatsUITests/`. The [Project Structure](#project-structure) section below summarizes their contents.
- **Backend:** `supabase/` holds the database migrations, row-level security policies, and edge functions. Deploying `delete-account`: [docs/runbooks/delete-account-deploy.md](docs/runbooks/delete-account-deploy.md).
- **Web app:** goes in `web/` when the 1.2 milestone starts. It doesn't exist yet.
- **Shared test data:** `shared/fixtures/stats/` holds stat definitions, datasets, and a reference calculator; `shared/fixtures/sync/` holds sync schemas, examples, and contract tests. The Deno fixture tests run in the Shared fixtures CI job. The iOS and future web suites can use these contracts; they are not part of the iOS unit-test count.
- **Specs:** product specs are in `docs/specs/`. [Sprint2plan.md](docs/history/Sprint2plan.md) and the plans under `docs/superpowers/` are historical records, not current process instructions.
- **Backlog:** this repo's issues, ranked in [#17](https://github.com/rohanthomas1202/PokerStats/issues/17). The `ios`, `backend`, and `web` lane labels decide which engineer takes an item.
- **CI:** each pull request runs only the jobs its changes touch, and one check, `CI passed`, reports the result ([#98](https://github.com/rohanthomas1202/PokerStats/issues/98)). The `Detect changes` job runs `ci-areas-test.sh` before it picks the jobs. See [Continuous Integration](#continuous-integration).
- **Review rules:** `.github/CODEOWNERS` sets who must review each path ([#99](https://github.com/rohanthomas1202/PokerStats/issues/99)).
- **Releases:** `.github/workflows/ios-release.yml` uploads iOS builds only from tags. An `ios-sprint-N` tag uploads a TestFlight build for testers. An `ios-vX.Y` tag uploads an App Store build, and each of those uploads waits for the owner's approval through the `app-store` environment and the `APP_STORE_UPLOAD_ENABLED` variable. CI never submits for review; the owner does that by hand. [#100](https://github.com/rohanthomas1202/PokerStats/issues/100) and [#31](https://github.com/rohanthomas1202/PokerStats/issues/31) stay open until the owner setup is done and a dry run on `main` is green (see Releases).
- **Build and release scripts:** `fastlane/` holds the fastlane lanes, `ci_scripts/` holds the Xcode Cloud and build-number scripts, and `.github/scripts/` holds the scripts and tests the CI workflows call.

---

## Project Structure

This is a directory guide, not an exhaustive file inventory. See the linked folders for current files.

| Path | Contents |
|------|----------|
| [`PokerStats/App/`](PokerStats/App/) | App entry, four-tab navigation, auth and auto-restore setup |
| [`PokerStats/Models/`](PokerStats/Models/) | SwiftData models, table configuration, computed stats, cloud DTOs, Live Activity attributes |
| [`PokerStats/Views/`](PokerStats/Views/) | Dashboard, session logging, history, trends, analysis, auth, settings, shared components |
| [`PokerStats/ViewModels/`](PokerStats/ViewModels/) | Screen state, hand logger flow, auth, backup, restore, local data ownership |
| [`PokerStats/Services/`](PokerStats/Services/) | Stat/trend calculators, leak analysis, position tracking, recovery, auth, backup/restore, local cleanup |
| [`PokerStats/Repositories/`](PokerStats/Repositories/) | Session repository protocol and SwiftData implementation |
| [`PokerStatsWidgets/`](PokerStatsWidgets/) | Home screen widget and Live Activity extension |
| [`PokerStatsTests/`](PokerStatsTests/) | iOS unit suites and test helpers, including auth, backup/restore, deletion, widgets, stats and position tracking |
| [`PokerStatsUITests/`](PokerStatsUITests/) | UI screenshot tests, separate from the iOS CI unit-test job |
| `project.yml` | XcodeGen targets, packages, build settings, and pre-build configuration |

---

## Architecture

### MVVM with @Observable

Screen ViewModels use `@Observable` with `@MainActor` isolation. The app accesses SwiftData through its model contexts; `AppGroupContainer` creates the shared store for the app and widget. Stat, trend, and leak calculations derive results from recorded data on demand.

`AuthService` coordinates Supabase authentication, backup scheduling, and account deletion. `BackupService` serializes local data into versioned payloads, uploads them to Storage, and records metadata through PostgREST. `LocalDataRestorer` validates payloads and replaces local records in a separate context with a single save. Local data ownership checks prevent backing up another account's stats. These are backups, not a live sync engine.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│    Views     │────>│  ViewModels  │────>│  StatCalculator  │
│  (SwiftUI)  │     │ (@Observable)│     │  (Pure Functions) │
└─────────────┘     └──────────────┘     └─────────────────┘
                           │
                    ┌──────┴───────┐
                    │ ModelContext │
                    │  (SwiftData) │
                    └──────────────┘
```

### Key Design Decisions

| Decision | Why |
|----------|-----|
| **MVVM** | Screen state lives in observable ViewModels; views handle presentation |
| **SwiftData over Core Data** | Modern, less boilerplate, native `@Query` integration |
| **On-demand stat computation** | Derive statistics from raw hands rather than storing separate stat totals |
| **Inline money fields on Session** | No separate entity needed — one financial record per session |
| **Enum-based hand model** | Matches the UI flow directly; computed properties derive stat flags |
| **Timer from persisted startTime** | Uses `TimelineView` — survives app crashes by design |

### Data Model

- `Session` stores dates, location, game type, stakes, status, notes, buy-in, rebuys, add-ons, cash-out, tip/rake, and optional tilt/energy/focus levels. Optional encoded `TableConfig` stores seats and button calibration. Net profit is cash-out minus buy-in, rebuys, and add-ons; hourly rate and ROI are computed.
- `Session.hands` has a cascade-delete relationship to `Hand`. Each hand stores its UUID, number, timestamp, position, preflop action, 3-bet response, postflop result, c-bet choice, and notes. Computed flags feed the calculators.
- `Settings` stores default game type, stakes, buy-in, and currency. Live Activity visibility is a separate preference.
- `BackupPayload` contains a schema version, creation date, app version, session/hand DTOs, and optional settings. `BackupMetadata` identifies the account's Storage object and records its counts, size, and schema version. Cloud DTOs are separate from SwiftData models.

### Data Flow

```
Hand Logger → Hand(@Model) → StatCalculator → ComputedStats → Dashboard/Detail Views
                  │
           Session(@Model) ──→ netProfit, hourlyRate, roi (computed)
```

---

## Testing

The iOS unit suites cover stat formulas with known-input/output validation and worked examples, plus auth, backup/restore, deletion, local ownership, widgets, and presentation helpers.

### Test Suites

[`PokerStatsTests/`](PokerStatsTests/) contains **459 `@Test` declarations in 35 `@Suite` files**, plus two helper files, counted at base `39ef84c`. The green [CI run 42495410942](https://github.com/rohanthomas1202/PokerStats/actions/runs/42495410942), at PR #353 head `ba38111` before its squash merge, reported **459 tests in 35 suites passed**.

That is the iOS unit-test count, not the monorepo total. The iOS job uses `-only-testing:PokerStatsTests`; it does not run `PokerStatsUITests`, Deno edge-function tests, pgTAP database tests, or shared fixture tests. The Deno, database, and shared fixture jobs were path-filter skipped in that run.

### Worked Examples

1. **Tight-Aggressive (10 hands)** — VPIP=50%, PFR=40%, WTSD=75%, W$SD=66.7%
2. **Loose-Passive (5 hands)** — VPIP=80%, PFR=20%, WTSD=75%, W$SD=33.3%
3. **Single Folded Hand** — VPIP=0%, PFR=0%, all other stats nil

### Run Tests

```bash
# Command line
xcodebuild test -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Xcode
Cmd + U
```

### Continuous Integration

GitHub Actions runs `.github/workflows/ci.yml` on every pull request to `main` and on every push to `main`. The **Detect changes** job passes the pull request's changed paths to `.github/scripts/ci-areas.sh`, which decides whether the iOS, Deno, shared fixture, and database jobs run. A change under `.github/` runs all of those jobs, and a push to `main` runs everything. The **CI passed** job fails if any other job failed or was cancelled, so it is the one check to require. The jobs that do the work:

- **iOS build and test** (`macos-26` runner, Xcode 26.6): installs a pinned XcodeGen release, runs `xcodegen generate`, builds the `PokerStats` scheme for the newest available iOS 26 iPhone simulator with code signing off, then runs the `PokerStatsTests` unit tests. Unsigned builds have no App Group entitlement, so `AppGroupContainer` uses an in-memory store when it runs as a unit-test host; a normal launch without the App Group fails with a clear error instead. SwiftPM checkouts and the module cache are cached, and packages resolve only from the committed `Package.resolved`. If tests fail, the `.xcresult` bundle is uploaded as a run artifact. The fastlane screenshot UI tests are not run in CI. CI has no `.env` file and no secrets: the pre-build script writes a placeholder `Secrets.plist`. The build gets its build number from `ci_scripts/build_number.sh`, and `ci_scripts/check_build_numbers.sh` checks that the built app and every `.appex` in its `PlugIns` folder carry it, with the app's version. The check fails if `PlugIns/PokerStatsWidgets.appex` is missing. It looks only at `PlugIns/*.appex`: an ExtensionKit extension under `Extensions/`, an App Clip or a nested extension is not checked, so extend the script before adding a target like that. Build numbers are UTC timestamps (`YYYYMMDDHHMMSS`, 14 digits) from now on, and they can't go back to a smaller counter: once a timestamp build is uploaded for a version, App Store Connect rejects a later build of that version unless its number is higher. Any other upload path, such as Xcode Cloud (#66), must use `ci_scripts/build_number.sh` or start above the latest timestamp build.
- **Release scripts** (`ubuntu-latest`, every run): `.github/scripts/ios-release-test.sh` tests the tag parsing, the TestFlight notes, `fastlane/asc_key.rb`, the upload gates in `ios-release.yml` and the Fastfile, and the package lock: `build_app` passes `disable_package_automatic_updates: true`, both upload lanes call `ci_scripts/generate_project.sh`, the `release` lane alone passes `APP_STORE_SUBMISSION` (run against stand-in fastlane actions, with mutated Fastfile copies that must fail, and `project.yml`, the workflows and `ci_scripts/` must not set it), and `generate_project.sh`, run in a throwaway repo with a stand-in `xcodegen` that deletes `Package.resolved`, puts the file back and fails when it is missing, uncommitted or changed. `.github/scripts/build-numbers-test.sh` tests `ci_scripts/build_number.sh` (14 digits, two runs a second apart differ) and runs `ci_scripts/check_build_numbers.sh` on fake app bundles, with a Python stand-in for PlistBuddy. It also runs the Fastfile's check line on an archive path with a space and a single quote.
- **Repo settings files** (`ubuntu-latest`, every run): `.github/scripts/repo-settings-test.sh` checks that `.github/rulesets/main.json` and `ios-tags.json` parse and hold the agreed settings, and that `main.json` requires exactly the gate job's name from `ci.yml`, so renaming **CI passed** fails CI. It also runs `.github/scripts/repo-settings-check.sh` against a stand-in `gh` and fails if the check makes any call other than a plain GET.
- **Edge functions (Deno)** (`ubuntu-latest`): runs `deno check` and `deno test` in each folder under `supabase/functions/`.
- **Shared fixtures** (`ubuntu-latest`): runs the Deno tests in `shared/fixtures/sync/` and `shared/fixtures/stats/` when backend or shared files change.
- **Database tests (pgTAP)** (`ubuntu-latest`): applies migrations to a local Supabase Postgres instance, runs `supabase test db`, and checks that a deliberately weakened profiles policy fails the tests. Runs when backend or CI configuration files change.
- **Privacy manifest declarations** (`ubuntu-latest`, runs when the iOS job does): `.github/scripts/privacy-api-check.sh` greps the app's and the widget extension's non-test Swift sources (the widget's list comes from `project.yml`) for required-reason APIs (UserDefaults, file timestamps, system boot time, disk space, active keyboards) and fails unless each category found is declared with a reason in that target's `PrivacyInfo.xcprivacy` (`PokerStats/PrivacyInfo.xcprivacy`, `PokerStatsWidgets/PrivacyInfo.xcprivacy`). Files under a folder named `PokerStatsTests/` or `PokerStatsUITests/`, at any depth, are skipped as tests; no other folder counts as a test folder. For the widget it reads each source's `path` and ignores excludes, so it can scan more files than the target builds, never fewer. It covers first-party Swift sources only: third-party SPM packages ship their own privacy manifests, which it does not read. It does not check that a declared reason code fits the category. It is a grep, so an API it does not list is not caught. The iOS job also prints the built app's manifest with `plutil -p`.
- **Fastlane never submits** (`ubuntu-latest`, every run): `.github/scripts/fastlane-no-submit.sh` fails if a file under `fastlane/`, `.github/workflows/` or `ci_scripts/` sets `submit_for_review` or `automatic_release` to a literal true value (`true`, `yes`, `on` or `1`, any case) in one of these forms: a Ruby key, hash rocket, call or assignment (`key: true`, `:key => true`, `key(true)`, `key true`, `key = true`), a positional symbol key (`store(:submit_for_review, true)`), a setter symbol (`send(:submit_for_review=, true)`), an env or YAML setting (`DELIVER_SUBMIT_FOR_REVIEW=yes`, `KEY: "true"`, also behind a YAML tag such as `!!bool` or an `&anchor`), or a bare CLI flag (`--submit_for_review` with no value). After a separator (`:`, `=>`, `=`, `(` or one of those commas) the value may be on the next line. It also catches an `ENV.fetch` default when the env var name contains the key (`ENV.fetch("DELIVER_AUTOMATIC_RELEASE", "true")`) or when the key is set to the `ENV.fetch` call (`submit_for_review: ENV.fetch("ANY_NAME", "true")`), with or without parentheses and with nested `ENV.fetch` defaults. It does not detect values set in variables or options hashes, expressions such as `false || true`, an `ENV.fetch` block default, a comment line between the key and its value, or env vars set in the Xcode Cloud UI. Known false positives: a quoted key or a symbol key followed by a comma and a true word fails the check, even in a comment (`"submit_for_review", on` or `# options like :submit_for_review, on demand only`). Only those three paths are scanned, so a release script added anywhere else (the repo root, a Makefile, `.github/scripts/`) must also be added to the path list in `ci.yml`. The owner submits to App Review by hand.
- **App Store metadata** (`ubuntu-latest`, every run): `.github/scripts/app-store-metadata-check.sh` checks the text files in `fastlane/metadata/en-US` against Apple's limits, counting characters without the final newline: name and subtitle 30, keywords 100, promotional text 170, description and release notes 4000. Each file must be valid UTF-8 with a trailing newline and no carriage returns. Keywords must be one comma-separated line with no spaces next to the commas and no empty, repeated, or name.txt words. URL files must hold one `https://` URL. A missing file is skipped. `.github/scripts/app-store-metadata-check-test.sh` tests the check and runs it on the committed files. It does not upload anything.

Dependabot (`.github/dependabot.yml`) opens weekly PRs to update the GitHub Actions versions used in the workflow and the Swift packages in `Package.resolved`. A Swift package update PR must also update the `exactVersion` in `project.yml` and the Dependencies table.

### Releases

`.github/workflows/ios-release.yml` is the only workflow that uploads the iOS app. Pushes to `main` and changes to `web/` or `supabase/` never upload anything.

| Trigger | What happens |
| --- | --- |
| Push an `ios-sprint-N` tag | Uploads a build to TestFlight with "What to Test" notes. |
| Push an `ios-vX.Y` or `ios-vX.Y.Z` tag | Uploads the App Store build. The owner submits it for review by hand in App Store Connect, every time. CI never submits. |
| Run the workflow by hand (Actions > iOS release > Run workflow, on `main`) | Dry run: builds and signs, no upload. |

A tag must point at a commit on `main` whose "CI passed" check succeeded, or the run stops before building. Only one release runs at a time. Keep release scripts in `fastlane/`, `.github/workflows/` or `ci_scripts/`: the **Fastlane never submits** check scans only those paths. A script anywhere else must be added to its path list in `ci.yml`.

`ios-sprint-*` runs the `testflight` job (`fastlane ios beta`, TestFlight). `ios-v*` runs the `appstore` job (`fastlane ios release`, App Store Connect build upload only; never `submit_for_review`, and metadata and screenshots are skipped until #53 lands). Only the `release` lane adds `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE_SUBMISSION'` to the archive's xcargs, so an App Store build fails to compile while `AppLinks.supportEmail` is still the `[CONTACT_EMAIL]` placeholder (#225). The `#error` is keyed only on that condition, so resolving #76 means filling in the address and deleting the `#if APP_STORE_SUBMISSION` block in `AppLinks.swift`. The `beta` lane (TestFlight), CI and Debug builds never set it. Manual dispatch runs the `testflight` job with `fastlane ios beta dry_run:true` (build and sign only). The two jobs are exclusive, and the `testflight` job never calls the release lane. The "What to Test" notes for TestFlight are the commit subjects since the previous valid `ios-*` release tag (`.github/scripts/release-notes.sh`). Signing is cloud-managed: xcodebuild gets the App Store Connect API key (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`) with `-allowProvisioningUpdates` for both archive and export, so no certificate or profile is stored in the repo or in secrets. That covers the widget extension (Live Activity) and the App Group `group.com.rohanthomas.PokerStats`. Only dSYMs are kept as run artifacts, for 30 days; the repo is public, so the `.ipa` is not.

The `appstore` job runs in the `app-store` GitHub environment and fails at its first step unless the repository variable `APP_STORE_UPLOAD_ENABLED` is `true`. Once the owner setup below is done, every App Store upload waits for the owner's approval on that environment.

#### Owner setup

Do these steps in this order ([#31](https://github.com/rohanthomas1202/PokerStats/issues/31)). Uploads fail until the secrets are in place, and App Store uploads also fail until `APP_STORE_UPLOAD_ENABLED` is set.

1. Sign the App Store Connect agreement ([#66](https://github.com/rohanthomas1202/PokerStats/issues/66)). The App Store Connect API returns 403 until then.
2. Create the `testflight` and `app-store` environments (Settings > Environments).
3. Limit each environment's deployment branches and tags: `testflight` to `main` and `ios-sprint-*` tags, `app-store` to `ios-v*` tags. Do this before adding any secret. This stops a run from a non-matching ref, such as an edited copy of the workflow pushed on another branch, from reading the App Store Connect key. It does not stop a matching tag: an `ios-sprint-*` or `ios-v*` tag can point at any commit, including one on a side branch with an edited `ios-release.yml`, and that run gets the environment's secrets. Step 4 closes that gap.
4. Add a tag ruleset (Settings > Rules > Rulesets) that targets `ios-*` tags, turns on Restrict creations, Restrict updates and Restrict deletions, and adds the Repository admin role to the bypass list with the bypass mode set to Always (tags are not pushed through pull requests, so "For pull requests only" would block every tag push). On a personal-account repository the bypass list takes roles, apps and deploy keys, not individual users, so the owner gets the bypass through the admin role. Pushing a tag is what starts an upload. Together with step 3, only the people the ruleset allows can start a tag run. That includes anything signed in as the owner's account: the bots push with the same login, so they share the admin bypass and can create, move or delete `ios-*` tags (creating a tag, or moving one with a forced update, is a push and starts a new run; deleting a tag does not start one) until [#147](https://github.com/rohanthomas1202/PokerStats/issues/147) is settled. A manual run (`workflow_dispatch`) on `main` is not covered: any collaborator with write access can start one, it runs the `testflight` job in the `testflight` environment, which reads the App Store Connect key, and it uses the workflow on `main`, so it is only as safe as branch protection on `main` ([#25](https://github.com/rohanthomas1202/PokerStats/issues/25)). This ruleset is in `.github/rulesets/ios-tags.json`, ready to import; [docs/runbooks/repo-settings.md](docs/runbooks/repo-settings.md) has the import steps, the `main` ruleset and Dependabot settings for #25, and a read-only check.
5. On `app-store`, add the owner as a required reviewer. GitHub creates a missing environment with no protection, and branch protection does not replace that reviewer.
6. Add the secrets below to both environments as environment secrets, not as repository secrets. A job outside those environments then gets no keys.
7. Set the repository variable `APP_STORE_UPLOAD_ENABLED=true` (Settings > Secrets and variables > Actions > Variables).
8. Run the workflow by hand on `main` as a dry run to confirm signing.

Both jobs need these secrets on `testflight` and `app-store`:

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`: the App Store Connect API key. Cloud-managed signing needs the Admin role, or App Manager with access to certificates.
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`: written to `.env` so the build gets the real `Secrets.plist`. The run fails rather than ship the placeholder values.

To close a sprint, Trevor - Release & Compliance tags the sprint-closing commit on `main` and records the build number, commit and notes for that sprint:

```bash
git tag ios-sprint-3 <commit-on-main>
git push origin ios-sprint-3
```

---

## Roadmap

- [x] **Dark theme UI redesign** — Custom color palette, range bars, play style labels
- [x] **Play style radar chart** — Diamond chart (TAG/LAG/ROCK/FISH classification)
- [x] **Trend charts** — Bankroll over time, VPIP/PFR trends, profit by day-of-week (Swift Charts)
- [x] **Tilt & energy tracker** — Self-report mood/focus, correlate with hourly rate
- [x] **Live Activities** — Lock screen session timer + home screen widget
- [x] **Leak Finder** — Automated coaching insights comparing stats to optimal ranges
- [x] **Position tracking** — Manual selection, automatic rotation with table calibration, per-position VPIP/PFR
- [x] **1.0 account and backup implementation** — Sign in with Apple, cloud backup/restore, account deletion, loading/retry states

The 1.0 release still has open acceptance and owner setup work. This list records implemented functionality, not an App Store or TestFlight launch.

Upcoming milestones are **1.1 Sync + sharing**, **1.2 Web**, and **1.3 Leaderboards**. After 1.0, Supabase is the single source of truth for user data. [iCloud sync #10](https://github.com/rohanthomas1202/PokerStats/issues/10#issuecomment-6248855748) is cancelled, not planned alongside Supabase sync.

New feature proposals are welcome. The ranked issues in [#17](https://github.com/rohanthomas1202/PokerStats/issues/17) track scope and priority; historical plans are not product restrictions.

---

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Ensure all tests pass (`Cmd + U` in Xcode)
5. Commit your changes (`git commit -m 'feat: add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Code Style

- Follow existing patterns (MVVM, `@Observable`, pure `StatCalculator` functions)
- Add unit tests for any new stat formulas
- Keep hand logging fast, with sub-3-second entry as the design goal rather than a guaranteed timing or fixed tap limit
- Third-party SPM packages are allowed; follow the [dependency policy](#policy)

---

## License

No `LICENSE` file is currently committed to this repository.

---

<p align="center">
  Built with SwiftUI + SwiftData
</p>
