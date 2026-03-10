<p align="center">
  <img src="https://img.icons8.com/color/96/000000/poker.png" alt="PokerStats Logo" width="80" height="80">
</p>

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
  <img src="https://img.shields.io/badge/tests-54%20passing-success?style=flat-square" alt="Tests">
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
- Playing tendency gauges (VPIP, PFR, C-Bet, WTSD)
- Active session banner with live timer
- Recent sessions at a glance

### Session History
- Full session list grouped by month
- Search by location or stakes
- Aggregate summary (total sessions, P&L, hours)
- Detailed session view with per-session stats and hand log

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

1. In Xcode, select **iPhone 16 Pro** (or any iOS 26+ simulator) from the device dropdown
2. Press **Cmd + R** to build and run

### 5. Run tests

```bash
xcodebuild test \
  -scheme PokerStats \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
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
│   │   └── ContentView.swift            # 3-tab navigation (Dashboard, Session, History)
│   │
│   ├── Models/
│   │   ├── Session.swift                # @Model: session with inline money tracking
│   │   ├── Hand.swift                   # @Model: hand with computed stat flags
│   │   ├── Settings.swift               # @Model: user preferences singleton
│   │   ├── Enums.swift                  # GameType, SessionStatus, PreflopAction, etc.
│   │   └── ComputedStats.swift          # Value type for aggregated statistics
│   │
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift     # Lifetime stats, recent sessions
│   │   ├── NewSessionViewModel.swift    # Session creation form state
│   │   ├── ActiveSessionViewModel.swift # Live session: timer, hands, money
│   │   ├── HandLoggerViewModel.swift    # State machine for hand entry flow
│   │   ├── SessionListViewModel.swift   # History filtering and grouping
│   │   ├── SessionDetailViewModel.swift # Single session stats + editing
│   │   └── SettingsViewModel.swift      # Preferences management
│   │
│   ├── Views/
│   │   ├── Dashboard/
│   │   │   └── DashboardView.swift      # Main dashboard with stats and recent sessions
│   │   ├── Session/
│   │   │   ├── SessionTabView.swift     # Context-aware: start vs active session
│   │   │   ├── StartSessionView.swift   # New session form
│   │   │   ├── ActiveSessionView.swift  # Live session with hand logging
│   │   │   ├── HandLoggerSheet.swift    # Progressive disclosure hand entry
│   │   │   └── EndSessionSummaryView.swift  # Session completion summary
│   │   ├── History/
│   │   │   ├── SessionHistoryView.swift # Searchable session list by month
│   │   │   ├── SessionRowView.swift     # Compact session row component
│   │   │   └── SessionDetailView.swift  # Detailed session with stats + hands
│   │   ├── Settings/
│   │   │   └── SettingsView.swift       # Defaults, data management, about
│   │   └── Components/
│   │       └── StatCardView.swift       # StatCardView, StatGaugeView, EmptyStateView, CurrencyField
│   │
│   ├── Services/
│   │   ├── StatCalculator.swift         # Pure stat computation (all formulas)
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
└── PokerStatsTests/
    ├── StatCalculatorTests.swift        # All stat formula tests + 3 worked examples
    ├── SessionTests.swift               # Session computed property tests
    ├── HandTests.swift                  # Hand computed flag tests
    └── TestHelpers.swift                # In-memory container + hand factories
```

**Total: 32 source files | 4 test files | 54 tests**

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

### Worked Examples

1. **Tight-Aggressive (10 hands)** — VPIP=50%, PFR=40%, WTSD=75%, W$SD=66.7%
2. **Loose-Passive (5 hands)** — VPIP=80%, PFR=20%, WTSD=75%, W$SD=33.3%
3. **Single Folded Hand** — VPIP=0%, PFR=0%, all other stats nil

### Run Tests

```bash
# Command line
xcodebuild test -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Xcode
Cmd + U
```

---

## Roadmap

- [ ] **Dark theme UI redesign** — Custom color palette, range bars, play style labels
- [ ] **Play style radar chart** — Diamond chart (TAG/LAG/ROCK/FISH classification)
- [ ] **Trend charts** — Bankroll over time, VPIP/PFR trends, profit by day-of-week (Swift Charts)
- [ ] **Tilt & energy tracker** — Self-report mood/focus, correlate with hourly rate
- [ ] **Live Activities** — Lock screen session timer + home screen widget
- [ ] **Leak Finder** — Automated coaching insights comparing stats to optimal ranges
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
