<h1 align="center">PokerStats</h1>

<p align="center">
  <strong>A native iOS app for live poker players to track sessions, log hands in real-time, and compute HUD-style statistics — all offline.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2026%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/swiftui-latest-purple?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/swiftdata-latest-green?style=flat-square" alt="SwiftData">
  <img src="https://img.shields.io/badge/tests-91%20passing-success?style=flat-square" alt="Tests">
</p>

---

## The Problem

Live poker players have no fast, mobile-first tool to track both financial results **and** playing tendencies. Existing apps are either money-only trackers (no hand data) or full hand-history tools designed for online poker (unusable at a live table). Without data, players can't identify leaks in their game.

## The Solution

PokerStats combines session-level financial tracking with a **sub-3-second hand-logging interaction**, enabling live poker players to compute statistics — **VPIP, PFR, 3-Bet%, C-Bet%, WTSD%, W$SD%** — that were previously only available through online poker HUD software.

---

## Features

### Session Management
- **One-tap session start** with buy-in, stakes, and location
- **Live session timer** computed from persisted start time (crash-proof)
- **Rebuy and add-on tracking** during active sessions
- **Cash-out and P&L auto-calculation** at session end
- **Session recovery** — kill the app mid-session and pick up right where you left off

### Hand Logger (Sub-3-Second Design)
The hand logger uses **progressive disclosure** to minimize taps:

| Scenario | Taps | Time |
|----------|------|------|
| Fold preflop | 1 | < 1s |
| Call, won/lost | 2 | ~1.5s |
| Raise, no 3-bet, won preflop | 3 | ~2s |
| Raise, saw flop + c-bet | 4 | ~2.5s |
| Raise, faced 3-bet, called, result + c-bet | 5 | ~3s |

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
- **Rolling VPIP/PFR** dual-line trend with configurable window
- **Profit by day of week** bar chart (green/red)
- **Session P&L distribution** histogram
- Time filter: All Time, 30 days, 90 days, 6 months

### Tilt & Energy Tracker
- Self-report **tilt, energy, and focus** (1–5 scale) at session start and mid-session check-ins
- **Mental correlation analysis** — hourly rate broken down by mental state level
- Per-session mental state badges in session detail

### Live Activities & Widgets
- **Lock screen Live Activity** during active sessions with timer, hand count, and invested amount
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

### Session History
- Full session list grouped by month
- Search by location or stakes
- Aggregate summary (total sessions, P&L, hours)
- Detailed session view with per-session stats, hand log, and session-specific leak insights

---

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Language** | Swift 6 | Latest stable with strict concurrency |
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
| supabase-swift (products Auth, Functions, PostgREST, Storage) | 2.55.4 | Supabase clients: Sign in with Apple and the session (Keychain storage, token refresh), backups in Storage, `backup_metadata` and `profiles` through PostgREST, and the `delete-account` edge function. Realtime is not used. | [supabase/supabase-swift](https://github.com/supabase/supabase-swift) |

`Package.resolved` also pins the packages supabase-swift depends on (swift-asn1, swift-clocks, swift-concurrency-extras, swift-crypto, swift-http-types, swift-issue-reporting, xctest-dynamic-overlay). They are not used by the app directly.

### Policy

When a PR adds, removes, or updates a package, the same PR must:

1. Declare it in `project.yml` under `packages:`, pinned to an `exactVersion` or `upToNextMinor` range (no `upToNextMajor`, branch, or revision pins).
2. Add or update its row in the table above: name, the exact version from `Package.resolved`, purpose, and repo link.
3. Commit the updated `PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

The table must match `Package.resolved` exactly. The rest of `PokerStats.xcodeproj` is generated by XcodeGen and gitignored, except the shared scheme in `xcshareddata/xcschemes/` and this `Package.resolved`. `xcodegen generate` can delete that file, so if it disappears after regenerating, run `git restore PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

### Tooling (not shipped in the app)

- **XcodeGen**: generates the Xcode project from `project.yml`. Installed with Homebrew, unpinned.
- **fastlane**: screenshots and App Store uploads (`fastlane/`). There is no `Gemfile`, so the version is not pinned. The `release` lane only uploads the build and metadata (`submit_for_review: false`, `automatic_release: false`). Submitting for App Review is manual and owner-only, done in App Store Connect. `ios-release.yml` runs `fastlane ios beta` for `ios-sprint-*` tags and `fastlane ios release` for `ios-v*` tags (see Releases). Ordinary CI never calls either upload lane. The `beta` and `release` lanes set the build number (`CFBundleVersion`) to the UTC time as `YYYYMMDDHHMMSS` from `ci_scripts/build_number.sh`, passed as `CURRENT_PROJECT_VERSION` so the app and its extensions match, then check the archive with `ci_scripts/check_build_numbers.sh` before uploading. The export sets `manageAppVersionAndBuildNumber` to false, so the uploaded IPA keeps the checked build number. See Continuous Integration for why build numbers can't go back to a smaller counter. The `CURRENT_PROJECT_VERSION` in `project.yml` is only the local default.
- **Supabase edge function** (`supabase/functions/delete-account`): imports `@supabase/supabase-js@2.118.0` from esm.sh and `@supabase/functions-js@2.118.0` from JSR (`deno.json`), both pinned to exact versions. Apple token revocation uses WebCrypto and `fetch` only, with no extra package. It needs the Edge Function secrets `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID` and `APPLE_PRIVATE_KEY`.

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
xcodegen generate
```

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

- **iOS app:** `PokerStats/`, `PokerStatsWidgets/`, `PokerStatsTests/`, and `PokerStatsUITests/`. The [Project Structure](#project-structure) section below lists their files.
- **Backend:** `supabase/` holds the database migrations, row-level security policies, and edge functions.
- **Web app:** goes in `web/` when the 1.2 milestone starts. It doesn't exist yet.
- **Shared test data:** goes in `shared/fixtures/`. The iOS and web test suites will both read it, so the two compute the same stats. It doesn't exist yet.
- **Specs:** product specs are in `docs/specs/`.
- **Backlog:** this repo's issues, ranked in [#17](https://github.com/rohanthomas1202/PokerStats/issues/17). The `ios`, `backend`, and `web` lane labels decide which engineer takes an item.
- **CI:** each pull request runs only the jobs its changes touch, and one check, `CI passed`, reports the result ([#98](https://github.com/rohanthomas1202/PokerStats/issues/98)). The `Detect changes` job runs `ci-areas-test.sh` before it picks the jobs. See [Continuous Integration](#continuous-integration).
- **Review rules:** `.github/CODEOWNERS` sets who must review each path ([#99](https://github.com/rohanthomas1202/PokerStats/issues/99)).
- **Releases:** `.github/workflows/ios-release.yml` uploads iOS builds only from tags. An `ios-sprint-N` tag uploads a TestFlight build for testers. An `ios-vX.Y` tag uploads an App Store build, and each of those uploads waits for the owner's approval through the `app-store` environment and the `APP_STORE_UPLOAD_ENABLED` variable. CI never submits for review; the owner does that by hand. [#100](https://github.com/rohanthomas1202/PokerStats/issues/100) and [#31](https://github.com/rohanthomas1202/PokerStats/issues/31) stay open until the owner setup is done and a dry run on `main` is green (see Releases).
- **Build and release scripts:** `fastlane/` holds the fastlane lanes, `ci_scripts/` holds the Xcode Cloud and build-number scripts, and `.github/scripts/` holds the scripts and tests the CI workflows call.

---

## Project Structure

```
PokerStats/
├── project.yml                          # XcodeGen project definition
├── PokerStats/
│   ├── App/
│   │   ├── PokerStatsApp.swift          # Entry point, ModelContainer setup
│   │   └── ContentView.swift            # 4-tab navigation (Dashboard, Session, Trends, History)
│   │
│   ├── Models/
│   │   ├── Session.swift                # @Model: session with inline money tracking
│   │   ├── Hand.swift                   # @Model: hand with computed stat flags
│   │   ├── Settings.swift               # @Model: user preferences singleton
│   │   ├── Enums.swift                  # GameType, SessionStatus, PreflopAction, MentalMetricType, etc.
│   │   ├── ComputedStats.swift          # Value type for aggregated statistics
│   │   └── SessionActivityAttributes.swift # Live Activity attributes for active sessions
│   │
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift     # Lifetime stats, recent sessions
│   │   ├── NewSessionViewModel.swift    # Session creation form state
│   │   ├── ActiveSessionViewModel.swift # Live session: timer, hands, money
│   │   ├── HandLoggerViewModel.swift    # State machine for hand entry flow
│   │   ├── SessionListViewModel.swift   # History filtering and grouping
│   │   ├── SessionDetailViewModel.swift # Single session stats + editing
│   │   ├── TrendsViewModel.swift        # Trend chart data + time filtering
│   │   ├── LeakFinderViewModel.swift    # Leak analysis, profile selection
│   │   └── SettingsViewModel.swift      # Preferences management
│   │
│   ├── Views/
│   │   ├── Dashboard/
│   │   │   └── DashboardView.swift      # Main dashboard with stats and recent sessions
│   │   ├── Session/
│   │   │   ├── SessionTabView.swift     # Context-aware: start vs active session
│   │   │   ├── StartSessionView.swift   # New session form with mental sliders
│   │   │   ├── ActiveSessionView.swift  # Live session with hand logging + check-in
│   │   │   ├── HandLoggerSheet.swift    # Progressive disclosure hand entry
│   │   │   ├── MentalCheckSheet.swift   # Mid-session tilt/energy/focus check-in
│   │   │   └── EndSessionSummaryView.swift  # Session completion summary
│   │   ├── History/
│   │   │   ├── SessionHistoryView.swift # Searchable session list by month
│   │   │   ├── SessionRowView.swift     # Compact session row component
│   │   │   └── SessionDetailView.swift  # Session stats, hand log, and per-session insights
│   │   ├── Trends/
│   │   │   └── TrendsView.swift         # 4 Swift Charts (bankroll, VPIP/PFR, day-of-week, P&L)
│   │   ├── Analysis/
│   │   │   └── LeakFinderView.swift     # Profile picker, health summary, insight cards
│   │   ├── Settings/
│   │   │   └── SettingsView.swift       # Defaults, data management, about
│   │   ├── Theme/
│   │   │   └── PokerTheme.swift         # Dark color palette, spacing tokens, card modifier
│   │   └── Components/
│   │       ├── StatCardView.swift       # StatCardView, StatGaugeView, EmptyStateView, CurrencyField
│   │       ├── RangeBarView.swift       # Gradient bar with indicator dot and good-range overlay
│   │       ├── StatHelpView.swift       # Stat definitions with help sheet
│   │       ├── PlayStyleChartView.swift # Diamond radar chart (TAG/LAG/ROCK/FISH)
│   │       ├── PlayStyleLabel.swift     # Play style classification + badge
│   │       ├── CircularGaugeView.swift  # Gradient ring gauge with center text
│   │       ├── MentalMetricSlider.swift # 5-dot tappable scale for tilt/energy/focus
│   │       └── InsightCardView.swift    # Expandable leak insight with severity bar
│   │
│   ├── Services/
│   │   ├── StatCalculator.swift         # Pure stat computation (all formulas)
│   │   ├── TrendCalculator.swift        # Time-series data for charts + mental correlation
│   │   ├── LeakFinder.swift             # Stat analysis vs optimal ranges, coaching insights
│   │   ├── AppGroupContainer.swift      # Shared ModelContainer for widget extension
│   │   └── SessionRecoveryService.swift # Active session crash recovery
│   │
│   ├── Repositories/
│   │   └── SessionRepository.swift      # Protocol + SwiftData CRUD implementation
│   │
│   ├── Utilities/
│   │   ├── CurrencyFormatter.swift      # Locale-aware money formatting
│   │   ├── DurationFormatter.swift      # TimeInterval → "2h 15m" or "01:23:45"
│   │   └── DateFormatting.swift         # Shared date formatters
│   │
│   ├── Resources/
│   │   └── Assets.xcassets              # App icon, accent color
│   │
│   └── Preview Content/
│       └── PreviewSampleData.swift      # Sample data for SwiftUI previews
│
├── PokerStatsWidgets/
│   ├── PokerStatsWidgetBundle.swift     # Widget bundle (Live Activity + Home Screen)
│   ├── PokerStatsLiveActivity.swift     # Lock screen + Dynamic Island live activity
│   └── PokerStatsLifetimeWidget.swift   # Home screen widget (small + medium)
│
└── PokerStatsTests/
    ├── StatCalculatorTests.swift        # All stat formula tests + 3 worked examples
    ├── SessionTests.swift               # Session computed property tests
    ├── HandTests.swift                  # Hand computed flag tests
    ├── PlayStyleTests.swift             # Play style classification tests
    ├── TrendCalculatorTests.swift       # Trend chart data computation tests
    ├── TiltTrackerTests.swift           # Mental correlation tests
    ├── LeakFinderTests.swift            # Leak analysis, severity, profiles, edge cases
    └── TestHelpers.swift                # In-memory container + hand factories
```

**Total: 48 source files | 7 test files | 91 tests**

---

## Architecture

### MVVM with @Observable

All ViewModels use the `@Observable` macro with `@MainActor` isolation. SwiftData `@Model` objects are also `@MainActor`-isolated. Stats are computed on-demand — no caching needed at MVP scale.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│    Views     │────>│  ViewModels  │────>│  StatCalculator  │
│  (SwiftUI)  │     │ (@Observable)│     │  (Pure Functions) │
└─────────────┘     └──────────────┘     └─────────────────┘
                           │
                    ┌──────┴───────┐
                    │  Repository  │
                    │  (SwiftData) │
                    └──────────────┘
```

### Key Design Decisions

| Decision | Why |
|----------|-----|
| **MVVM over TCA** | App complexity doesn't warrant unidirectional data flow overhead |
| **SwiftData over Core Data** | Modern, less boilerplate, native `@Query` integration |
| **On-demand stat computation** | Sub-millisecond at MVP scale (< 10K hands), no caching complexity |
| **Inline money fields on Session** | No separate entity needed — one financial record per session |
| **Enum-based hand model** | Matches the UI flow directly; computed properties derive stat flags |
| **Timer from persisted startDate** | Uses `TimelineView` — survives app crashes by design |

### Data Flow

```
Hand Logger → Hand(@Model) → StatCalculator → ComputedStats → Dashboard/Detail Views
                  │
           Session(@Model) ──→ netProfit, hourlyRate, roi (computed)
```

---

## Testing

The test suite covers all stat formulas with known-input/output validation and three complete worked examples that trace hands through every formula.

### Test Suites

| Suite | Tests | Coverage |
|-------|-------|----------|
| `StatCalculatorTests` | 30 | VPIP, PFR, Fold-to-3B, C-Bet, WTSD, W$SD, money stats, aggregation + 3 worked examples |
| `HandTests` | 17 | All computed flags: voluntarilyPutMoneyIn, raisedPreflop, foldedPreflop, sawFlop, wentToShowdown, hadCBetOpportunity, actionSummary |
| `SessionTests` | 7 | totalInvested, netProfit, hourlyRate, roi, isActive, nextHandNumber |
| `PlayStyleTests` | 5 | TAG, Fish, Nit, Maniac classification + nil handling |
| `TrendCalculatorTests` | 12 | Cumulative bankroll, rolling VPIP/PFR, day-of-week, P&L distribution, mental correlation |
| `TiltTrackerTests` | 10 | Mental correlation computation, nil exclusion, averaging, edge cases |
| `LeakFinderTests` | 10 | Tight player (all healthy), loose player (leaks), nil stats, boundaries, borderline, overall ratings, sorting, profile comparison |

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

GitHub Actions runs `.github/workflows/ci.yml` on every pull request to `main` and on every push to `main`. The **Detect changes** job passes the pull request's changed paths to `.github/scripts/ci-areas.sh`, which decides whether the iOS and Deno jobs run. A change under `.github/` runs both, and a push to `main` runs everything. The **CI passed** job fails if any other job failed or was cancelled, so it is the one check to require. The jobs that do the work:

- **iOS build and test** (`macos-26` runner, Xcode 26.6): installs a pinned XcodeGen release, runs `xcodegen generate`, builds the `PokerStats` scheme for the newest available iOS 26 iPhone simulator with code signing off, then runs the `PokerStatsTests` unit tests. Unsigned builds have no App Group entitlement, so `AppGroupContainer` uses an in-memory store when it runs as a unit-test host; a normal launch without the App Group fails with a clear error instead. SwiftPM checkouts and the module cache are cached, and packages resolve only from the committed `Package.resolved`. If tests fail, the `.xcresult` bundle is uploaded as a run artifact. The fastlane screenshot UI tests are not run in CI. CI has no `.env` file and no secrets: the pre-build script writes a placeholder `Secrets.plist`. The build gets its build number from `ci_scripts/build_number.sh`, and `ci_scripts/check_build_numbers.sh` checks that the built app and every `.appex` in its `PlugIns` folder carry it, with the app's version. The check fails if `PlugIns` has no `.appex`. Build numbers are UTC timestamps (`YYYYMMDDHHMMSS`, 14 digits) from now on, and they can't go back to a smaller counter: once a timestamp build is uploaded for a version, App Store Connect rejects a later build of that version unless its number is higher. Any other upload path, such as Xcode Cloud (#66), must use `ci_scripts/build_number.sh` or start above the latest timestamp build.
- **Release scripts** (`ubuntu-latest`, every run): `.github/scripts/ios-release-test.sh` tests the tag parsing, the TestFlight notes, `fastlane/asc_key.rb` and the upload gates in `ios-release.yml` and the Fastfile. `.github/scripts/build-numbers-test.sh` tests `ci_scripts/build_number.sh` (14 digits, two runs a second apart differ) and runs `ci_scripts/check_build_numbers.sh` on fake app bundles, with a Python stand-in for PlistBuddy. It also runs the Fastfile's check line on an archive path with a space and a single quote.
- **Edge functions (Deno)** (`ubuntu-latest`): runs `deno check` and `deno test` in each folder under `supabase/functions/`.
- **Privacy manifest declarations** (`ubuntu-latest`, runs when the iOS job does): `.github/scripts/privacy-api-check.sh` greps the app's and the widget extension's non-test Swift sources (the widget's list comes from `project.yml`) for required-reason APIs (UserDefaults, file timestamps, system boot time, disk space, active keyboards) and fails unless each category found is declared with a reason in that target's `PrivacyInfo.xcprivacy` (`PokerStats/PrivacyInfo.xcprivacy`, `PokerStatsWidgets/PrivacyInfo.xcprivacy`). Only `PokerStatsTests/` and `PokerStatsUITests/` count as test folders. For the widget it reads each source's `path` and ignores excludes, so it can scan more files than the target builds, never fewer. It covers first-party Swift sources only: third-party SPM packages ship their own privacy manifests, which it does not read. It does not check that a declared reason code fits the category. It is a grep, so an API it does not list is not caught. The iOS job also prints the built app's manifest with `plutil -p`.
- **Fastlane never submits** (`ubuntu-latest`, every run): `.github/scripts/fastlane-no-submit.sh` fails if anything under `fastlane/`, `.github/workflows/` or `ci_scripts/` turns on `submit_for_review` or `automatic_release` with a literal true value (`true`, `yes`, `on` or `1`, also on the next line, after a YAML tag such as `!!bool` or an anchor, or as a bare CLI flag). It also catches an `ENV.fetch` default when the env var name contains the key (`ENV.fetch("DELIVER_AUTOMATIC_RELEASE", "true")`) or when the key is set to the `ENV.fetch` call (`submit_for_review: ENV.fetch("ANY_NAME", "true")`). It does not detect values set in variables, an `ENV.fetch` block default, a comment line between the key and its value, or env vars set in the Xcode Cloud UI. A quoted key followed by a comma and a true word, even in a comment (`"submit_for_review", on`), fails the check. Only those three paths are scanned, so a release script added anywhere else (the repo root, a Makefile, `.github/scripts/`) must also be added to the path list in `ci.yml`. The owner submits to App Review by hand.

Dependabot (`.github/dependabot.yml`) opens weekly PRs to update the GitHub Actions versions used in the workflow and the Swift packages in `Package.resolved`. A Swift package update PR must also update the `exactVersion` in `project.yml` and the Dependencies table.

### Releases

`.github/workflows/ios-release.yml` is the only workflow that uploads the iOS app. Pushes to `main` and changes to `web/` or `supabase/` never upload anything.

| Trigger | What happens |
| --- | --- |
| Push an `ios-sprint-N` tag | Uploads a build to TestFlight with "What to Test" notes. |
| Push an `ios-vX.Y` or `ios-vX.Y.Z` tag | Uploads the App Store build. The owner submits it for review by hand in App Store Connect, every time. CI never submits. |
| Run the workflow by hand (Actions > iOS release > Run workflow, on `main`) | Dry run: builds and signs, no upload. |

A tag must point at a commit on `main` whose "CI passed" check succeeded, or the run stops before building. Only one release runs at a time. Keep release scripts in `fastlane/`, `.github/workflows/` or `ci_scripts/`: the **Fastlane never submits** check scans only those paths. A script anywhere else must be added to its path list in `ci.yml`.

`ios-sprint-*` runs the `testflight` job (`fastlane ios beta`, TestFlight). `ios-v*` runs the `appstore` job (`fastlane ios release`, App Store Connect build upload only; never `submit_for_review`, and metadata and screenshots are skipped until #53 lands). Manual dispatch runs the `testflight` job with `fastlane ios beta dry_run:true` (build and sign only). The two jobs are exclusive, and the `testflight` job never calls the release lane. The "What to Test" notes for TestFlight are the commit subjects since the previous valid `ios-*` release tag (`.github/scripts/release-notes.sh`). Signing is cloud-managed: xcodebuild gets the App Store Connect API key (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`) with `-allowProvisioningUpdates` for both archive and export, so no certificate or profile is stored in the repo or in secrets. That covers the widget extension (Live Activity) and the App Group `group.com.rohanthomas.PokerStats`. Only dSYMs are kept as run artifacts, for 30 days; the repo is public, so the `.ipa` is not.

The `appstore` job runs in the `app-store` GitHub environment and fails at its first step unless the repository variable `APP_STORE_UPLOAD_ENABLED` is `true`. Once the owner setup below is done, every App Store upload waits for the owner's approval on that environment.

#### Owner setup

Do these steps in this order ([#31](https://github.com/rohanthomas1202/PokerStats/issues/31)). Uploads fail until the secrets are in place, and App Store uploads also fail until `APP_STORE_UPLOAD_ENABLED` is set.

1. Sign the App Store Connect agreement ([#66](https://github.com/rohanthomas1202/PokerStats/issues/66)). The App Store Connect API returns 403 until then.
2. Create the `testflight` and `app-store` environments (Settings > Environments).
3. Limit each environment's deployment branches and tags: `testflight` to `main` and `ios-sprint-*` tags, `app-store` to `ios-v*` tags. Do this before adding any secret. This stops a run from a non-matching ref, such as an edited copy of the workflow pushed on another branch, from reading the App Store Connect key. It does not stop a matching tag: an `ios-sprint-*` or `ios-v*` tag can point at any commit, including one on a side branch with an edited `ios-release.yml`, and that run gets the environment's secrets. Step 4 closes that gap.
4. Add a tag ruleset (Settings > Rules > Rulesets) that targets `ios-*` tags, turns on Restrict creations, Restrict updates and Restrict deletions, and adds the Repository admin role to the bypass list with the bypass mode set to Always (tags are not pushed through pull requests, so "For pull requests only" would block every tag push). On a personal-account repository the bypass list takes roles, apps and deploy keys, not individual users, so the owner gets the bypass through the admin role. Pushing a tag is what starts an upload. Together with step 3, only the people the ruleset allows can start a tag run. That includes anything signed in as the owner's account: the bots push with the same login, so they share the admin bypass and can create, move or delete `ios-*` tags (a forced tag update is a push and starts a new run) until [#147](https://github.com/rohanthomas1202/PokerStats/issues/147) is settled. A manual run (`workflow_dispatch`) on `main` is not covered: any collaborator with write access can start one, it runs the `testflight` job in the `testflight` environment, which reads the App Store Connect key, and it uses the workflow on `main`, so it is only as safe as branch protection on `main` ([#25](https://github.com/rohanthomas1202/PokerStats/issues/25)).
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
- [ ] **Position tracking** — Per-position stat breakdowns (UTG, MP, CO, BTN, SB, BB)
- [ ] **Tournament support** — Buy-ins, placements, ICM
- [ ] **Data export** — CSV/JSON export via ShareLink
- [ ] **iCloud sync** — Cross-device backup with CloudKit

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
- Keep the hand logger under 3 seconds for the longest path
- Third-party SPM packages are allowed; follow the [dependency policy](#policy)

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Built with SwiftUI + SwiftData
</p>
