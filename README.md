<h1 align="center">PokerStats</h1>

<p align="center">
  <strong>A native iOS app for live poker players to track sessions, log hands in real-time, and compute HUD-style statistics — all offline.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2026%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/swiftui-latest-purple?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/swiftdata-latest-green?style=flat-square" alt="SwiftData">
  <img src="https://img.shields.io/badge/dependencies-zero-brightgreen?style=flat-square" alt="Dependencies">
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
| **Dependencies** | Zero | Fully native, no third-party libraries |

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
- Zero third-party dependencies policy

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Built with SwiftUI + SwiftData
</p>
