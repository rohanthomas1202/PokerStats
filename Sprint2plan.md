# PokerStats — UI Redesign + 5 New Features Plan

## Context

The PokerStats MVP is complete and functional (sessions, hand logging, stats, dashboard, history). The user wants 7 phases of improvements:

- **Phases 1-2**: Dark-themed UI redesign inspired by reference screenshots (dark cards, range bars, play style radar chart, circular gauges, help icons)
- **Phase 3**: Trend Charts (Swift Charts)
- **Phase 4**: Tilt & Energy Tracker
- **Phase 5**: Live Activities & Widgets
- **Phase 6**: Leak Finder / Coaching Insights
- **Phase 7**: Position Tracking

Each phase must build, pass tests, and include manual test steps before proceeding to the next.

---

## Phase 1: Design System & Core Components

**Goal**: Replace the frosted-glass material theme with a pure dark theme. Create reusable components: range bars, help icons, play style labels.

### New Files

| File | Purpose |
|------|---------|
| `Views/Theme/PokerTheme.swift` | Color palette (`.pokerBackground`, `.pokerCard`, `.pokerProfit`, `.pokerLoss`, etc.), spacing tokens, `.pokerCard()` ViewModifier replacing all `ultraThinMaterial` |
| `Views/Components/RangeBarView.swift` | Horizontal gradient bar (green→yellow→red) with dot indicator showing where a stat value falls. Takes `value`, `goodRange`, `isInverted` |
| `Views/Components/StatHelpView.swift` | `StatDefinition` enum (vpip, pfr, cBet, etc.) with `title`, `explanation`, `idealRange`. `StatHelpButton` (small `?` circle) that presents a help sheet |
| `Views/Components/PlayStyleLabel.swift` | `PlayStyle` enum (`.nit`, `.rock`, `.tag`, `.lag`, `.fish`, `.maniac`, `.passive`) with `classify(vpip:pfr:)`. `PlayStyleLabelView` badge |

### Modified Files

| File | Changes |
|------|---------|
| `App/PokerStatsApp.swift` | Add `.preferredColorScheme(.dark)` to root WindowGroup |
| `App/ContentView.swift` | Add `.background(Color.pokerBackground)` |
| `Views/Components/StatCardView.swift` | Replace `ultraThinMaterial` with `.pokerCard()`. Add optional `statDef: StatDefinition?` for help button. Add optional `rangeValue/rangeGoodRange` for RangeBarView. Split value text into number + "%" suffix at different sizes. Update all colors to theme. Same for StatGaugeView (increase to 80x80, 8pt stroke), EmptyStateView, CurrencyField |
| `Views/Dashboard/DashboardView.swift` | Theme only — swap material backgrounds, update colors to `.pokerProfit`/`.pokerLoss`/`.pokerTextSecondary`. Add `PlayStyleLabelView` next to "Playing Tendencies" header |
| `Views/Session/ActiveSessionView.swift` | Theme backgrounds, pills, timer, buttons |
| `Views/Session/StartSessionView.swift` | Theme backgrounds, pills, text fields |
| `Views/Session/EndSessionSummaryView.swift` | Theme backgrounds, colors |
| `Views/Session/HandLoggerSheet.swift` | Theme progress dots, backgrounds |
| `Views/History/SessionDetailView.swift` | Theme all material cards |
| `Views/History/SessionHistoryView.swift` | Theme list, `.scrollContentBackground(.hidden)` |
| `Views/History/SessionRowView.swift` | Theme P&L colors |
| `Views/Settings/SettingsView.swift` | Theme form background |

### Build Order
1. `PokerTheme.swift` (foundation — everything depends on this)
2. `RangeBarView.swift`, `StatHelpView.swift`, `PlayStyleLabel.swift` (parallel)
3. `StatCardView.swift` (depends on above)
4. `PokerStatsApp.swift` + `ContentView.swift` (dark mode toggle)
5. All view files (parallel, each only depends on theme + components)

### Tests
- Unit test `PlayStyle.classify(vpip:pfr:)`: TAG (0.22, 0.18), Fish (0.45, 0.08), Nit (0.08, 0.06), Maniac (0.50, 0.40), nil→nil
- New file: `PokerStatsTests/PlayStyleTests.swift`

### Manual Test Steps
1. Launch app — every screen should have pure black background
2. Dashboard: stat cards have dark gray background with subtle border, not frosted glass
3. Tap `?` icon on any stat card → help sheet appears with explanation
4. Play style badge shows next to "Playing Tendencies" (or "--" if no data)
5. Start Session screen: dark theme, accent-colored buttons
6. Hand Logger: dark background, themed progress dots
7. Session Detail: dark cards, range bars visible under stats
8. Verify no bright/white flashes during navigation transitions

---

## Phase 2: Dashboard Redesign & Play Style Chart

**Goal**: Restructure Dashboard layout into 2-column stat grid. Add radar chart and circular gauges. Apply new layout to SessionDetail and EndSessionSummary.

### New Files

| File | Purpose |
|------|---------|
| `Views/Components/PlayStyleChartView.swift` | Diamond/radar chart using `Canvas`. Axes: Tight↔Loose (x, derived from VPIP), Passive↔Aggressive (y, derived from PFR/VPIP ratio). Concentric diamond rings, colored quadrant zones (TAG/LAG/ROCK/FISH), player position dot with glow. ~250x250 frame |
| `Views/Components/CircularGaugeView.swift` | Larger gauge ring (100x100, 10pt stroke) with gradient color, center text (split number/%  typography), title + emoji below. For fold frequency and similar |

### Modified Files

| File | Changes |
|------|---------|
| `Views/Dashboard/DashboardView.swift` | **Major restructure**: (1) Active banner (keep). (2) Play Style section: `PlayStyleLabelView` + `PlayStyleChartView`. (3) Financial card: large P&L + 3-col sub-metrics. (4) Core stats 2-column grid: VPIP, PFR, C-Bet, WTSD — each with emoji, help icon, range bar. (5) Secondary stats 3-col: Fold-to-3B, W$SD, Fold%. (6) Fold Frequency section with `CircularGaugeView` for preflop fold % and fold-to-3-bet %. (7) Recent sessions with `.pokerCard()` per row |
| `ViewModels/DashboardViewModel.swift` | Add `playStyle: PlayStyle?` computed property. Add `foldPercent: Double?` computed |
| `Views/History/SessionDetailView.swift` | Redesign stats section: 2-col grid with range bars and help icons. Add `PlayStyleLabelView` + small `PlayStyleChartView`. Add ROI display |
| `Views/Session/EndSessionSummaryView.swift` | 2-col stat grid, `PlayStyleLabelView`, range bars |
| `Views/Session/ActiveSessionView.swift` | Replace horizontal pills with 2x2 mini stat card grid. Add `PlayStyleLabelView` in status area |
| `Views/History/SessionRowView.swift` | Add 4px colored vertical bar on leading edge (green/red) |
| `Preview Content/PreviewSampleData.swift` | Add diverse sample sessions: fish profile, TAG profile, maniac |

### Build Order
1. `PlayStyleChartView.swift` + `CircularGaugeView.swift` (parallel, new files)
2. `DashboardViewModel.swift` (small addition)
3. `DashboardView.swift` (major, depends on all above)
4. Other views (parallel)

### Tests
- Add `#Preview` blocks to `PlayStyleChartView` and `CircularGaugeView` with varied data
- Visual test on iPhone SE, iPhone 16, iPhone 16 Pro Max (verify 2-col grid doesn't clip)

### Manual Test Steps
1. Dashboard shows play style chart with correct quadrant position
2. Stats in 2-column grid with range bars and `?` icons
3. Fold frequency gauges render as large rings
4. Recent sessions have colored profit bars on left edge
5. Session Detail shows play style chart and 2-col stats
6. End Session Summary shows 2-col stats with range bars
7. Active Session shows 2x2 stat grid instead of horizontal pills
8. Test with 0 sessions — empty state still works
9. Test with 1 session — stats show without chart errors

---

## Phase 3: Trend Charts (Swift Charts)

**Goal**: Add a "Trends" tab with 4 charts: cumulative bankroll, VPIP/PFR rolling trends, profit by day-of-week, P&L distribution histogram.

### New Files

| File | Purpose |
|------|---------|
| `Services/TrendCalculator.swift` | Pure static functions: `cumulativeBankroll(sessions:)` → `[BankrollDataPoint]`, `rollingVPIPPFR(hands:windowSize:)` → `[RollingStatPoint]`, `profitByDayOfWeek(sessions:)` → `[DayOfWeekProfit]`, `sessionPLDistribution(sessions:bucketWidth:)` → `[PLBucket]`. Each return type is `Identifiable` struct |
| `ViewModels/TrendsViewModel.swift` | `@Observable @MainActor`. Properties: chart data arrays, `selectedTimeFilter` enum (allTime/30d/90d/6mo). `loadData(from:)` fetches sessions/hands, filters, calls TrendCalculator |
| `Views/Trends/TrendsView.swift` | `import Charts`. Segmented Picker for time filter. ScrollView with 4 chart sections in `.pokerCard()` containers. `LineMark` for bankroll, dual `LineMark` for VPIP/PFR, `BarMark` for day-of-week (green/red), `BarMark` for histogram. Empty state if <2 sessions |

### Modified Files

| File | Changes |
|------|---------|
| `App/ContentView.swift` | Add 4th tab: `Tab("Trends", systemImage: "chart.xyaxis.line", value: 3)` → `TrendsView()`. Shift History from value 2 to 3, Trends is value 2 (or keep order: Dashboard=0, Session=1, Trends=2, History=3) |

### Test File
`PokerStatsTests/TrendCalculatorTests.swift` — Test all 4 functions: 0 sessions→empty, 3 sessions→correct cumulative totals, day-of-week returns 7 entries, distribution bucketing

### Manual Test Steps
1. New "Trends" tab visible in tab bar
2. With 0 sessions: empty state message
3. Create 3+ sessions with varied P&L → bankroll chart shows line going up/down
4. Log 20+ hands → VPIP/PFR trend lines appear
5. Time filter changes which sessions are included
6. Profit by day-of-week bars are green (positive) or red (negative)
7. P&L distribution shows histogram of session results

---

## Phase 4: Tilt & Energy Tracker

**Goal**: Add tilt/energy/focus self-reporting (1-5 scale) on sessions. Show correlation with hourly rate.

### New Files

| File | Purpose |
|------|---------|
| `Views/Components/MentalMetricSlider.swift` | Row of 5 tappable circles (1-5) with `lowLabel`/`highLabel`, `icon`, `@Binding value: Int`. Color-coded: 1=green→5=red for tilt, inverted for energy/focus. Haptic on tap |
| `Views/Session/MentalCheckSheet.swift` | Sheet with 3 `MentalMetricSlider` instances + Save button |

### Modified Files

| File | Changes |
|------|---------|
| `Models/Session.swift` | Add `var tiltLevel: Int?`, `var energyLevel: Int?`, `var focusLevel: Int?`. Update `init` with nil defaults |
| `Models/Enums.swift` | Add `enum MentalMetricType: String, CaseIterable` with `.tilt`, `.energy`, `.focus` + display names, icons, labels |
| `App/PokerStatsApp.swift` | Add lightweight schema migration (V1→V2) for the 3 new optional fields. Use `SchemaMigrationPlan` |
| `ViewModels/NewSessionViewModel.swift` | Add tilt/energy/focus Int properties (default 3). Set on session in `createSession()` |
| `ViewModels/ActiveSessionViewModel.swift` | Add `isShowingMentalCheck`, tilt/energy/focus properties, `saveMentalLevels()` |
| `Views/Session/StartSessionView.swift` | Add "How are you feeling?" section with 3 `MentalMetricSlider` instances |
| `Views/Session/ActiveSessionView.swift` | Add "Check In" button in action row that presents `MentalCheckSheet` |
| `Views/History/SessionDetailView.swift` | Add "Mental State" card showing tilt/energy/focus levels (only if non-nil) |
| `Services/TrendCalculator.swift` | Add `mentalCorrelation(sessions:)` → `[MentalCorrelationPoint]` computing avg hourly rate by metric+level |
| `Views/Dashboard/DashboardView.swift` | Add small "Mental Insights" card: "When calm (tilt=1): +$X/hr" vs "When tilted (tilt=5): -$Y/hr" (only if enough data) |

### Test File
`PokerStatsTests/TiltTrackerTests.swift` — Test `mentalCorrelation`: sessions with various levels, nil exclusion, single-level edge case

### Manual Test Steps
1. Start new session → mental sliders appear, default at 3
2. Tap to adjust tilt/energy/focus → haptic feedback
3. During active session: "Check In" button → updates mental levels
4. End session → detail view shows mental state card
5. After 5+ sessions with mental data: dashboard shows correlation insight
6. Old sessions (without mental data): no mental card in detail, no crash

---

## Phase 5: Live Activities & Widgets

**Goal**: Lock screen Live Activity during sessions. Home screen widget with lifetime P&L.

### New Files

| File | Purpose |
|------|---------|
| `Models/SessionActivityAttributes.swift` | `ActivityAttributes` with `stakes`, `location`. `ContentState`: `elapsedSeconds`, `handCount`, `totalInvested`, `startTime` |
| `PokerStatsWidgets/PokerStatsWidgetBundle.swift` | `@main WidgetBundle` with `PokerStatsLiveActivity` + `PokerStatsLifetimeWidget` |
| `PokerStatsWidgets/PokerStatsLiveActivity.swift` | `ActivityConfiguration` — Lock Screen: timer + P&L + hands. Dynamic Island: compact (timer/hands), expanded (stakes + details) |
| `PokerStatsWidgets/PokerStatsLifetimeWidget.swift` | `StaticConfiguration` widget — lifetime P&L, sessions, streak. `systemSmall` and `systemMedium` families |
| `PokerStatsWidgets/AppGroupContainer.swift` | Shared `ModelContainer` using App Group `group.com.rohanthomas.PokerStats` |

### Modified Files

| File | Changes |
|------|---------|
| `project.yml` | Add `PokerStatsWidgets` app extension target with `SUPPORTS_LIVE_ACTIVITIES: YES`. Add App Group entitlements to main app + widget |
| `App/PokerStatsApp.swift` | Switch `ModelContainer` to use App Group shared container |
| `ViewModels/ActiveSessionViewModel.swift` | Add `Activity<SessionActivityAttributes>?` tracking. `startLiveActivity()` in init, `updateLiveActivity()` after hand/rebuy, `endLiveActivity()` on session end |
| `ViewModels/NewSessionViewModel.swift` | Start live activity after `createSession()` |

### Manual Test Steps
1. Start session → Live Activity appears on lock screen with timer, invested amount
2. Log a hand → Live Activity updates hand count
3. Add rebuy → invested amount updates
4. End session → Live Activity dismisses
5. Home screen widget shows lifetime P&L (add widget from widget gallery)
6. Kill app during session → Live Activity persists, resumes on relaunch

---

## Phase 6: Leak Finder / Coaching Insights

**Goal**: Automated analysis comparing stats against optimal ranges. Color-coded feedback with actionable suggestions.

### New Files

| File | Purpose |
|------|---------|
| `Services/LeakFinder.swift` | `StatRange` (optimal + acceptable ranges), `ReferenceProfile` (Full Ring Cash, 6-Max Cash with ranges for VPIP/PFR/Fold3B/CBet/WTSD/WSD), `LeakInsight` (statName, value, rating .healthy/.borderline/.leak, message, suggestion). `analyze(stats:profile:) -> [LeakInsight]` |
| `ViewModels/LeakFinderViewModel.swift` | `@Observable @MainActor`. `insights`, `selectedProfile`, `leakCount`, `overallRating`. `loadData(from:)` |
| `Views/Analysis/LeakFinderView.swift` | Profile picker, overall health indicator, list of `InsightCardView` items. Minimum 20 hands required |
| `Views/Components/InsightCardView.swift` | Card with colored left border (green/yellow/red), stat name + value, message, expandable suggestion |

### Modified Files

| File | Changes |
|------|---------|
| `Views/Dashboard/DashboardView.swift` | Add "Leak Finder" NavigationLink card between stats and recent sessions (only if totalHands >= 20) showing leak count + overall rating color |
| `Views/History/SessionDetailView.swift` | Optional per-session insights section |

### Test File
`PokerStatsTests/LeakFinderTests.swift` — Test analyze() with tight player (all healthy), loose player (VPIP+PFR leaks), nil stats (skipped), boundary values

### Manual Test Steps
1. Dashboard shows "Leak Finder" card (only with 20+ hands)
2. Tap → Leak Finder view with profile selector
3. Each stat shows green/yellow/red indicator with explanation
4. Switch profile (Full Ring ↔ 6-Max) → ratings may change
5. With <20 hands: empty state shown
6. Session detail shows per-session insights

---

## Phase 7: Position Tracking

**Goal**: Enable position selection in hand logger. Add position-based stat breakdowns.

### New Files

| File | Purpose |
|------|---------|
| `Views/Components/PositionStatsCardView.swift` | Compact card for one position: name, hand count, VPIP, PFR |

### Modified Files

| File | Changes |
|------|---------|
| `Models/Enums.swift` | Add to `SeatPosition`: `static var allPlayable` (excludes .unknown), `sortOrder: Int`, `longName: String` |
| `Models/ComputedStats.swift` | Add `struct PositionStats: Identifiable` with position, handCount, vpip, pfr, etc. |
| `Services/StatCalculator.swift` | Add `vpip(hands:position:)`, `pfr(hands:position:)`, `statsByPosition(hands:) -> [PositionStats]` |
| `ViewModels/HandLoggerViewModel.swift` | Add `position: SeatPosition = .unknown`. Add `.position` case to `LoggerStep` (before `.preflop`). Add `selectPosition(_:)` method. Update `goBack()`, `canGoBack`, `buildHand()`, `reset()` |
| `Views/Session/HandLoggerSheet.swift` | Add `.position` step: "Your Position" title, 2x3 grid of 6 position buttons (SB/BB/UTG/MP/CO/BTN) + "Skip" link. Update `totalSteps` to 6, `currentStepIndex` mapping |
| `ViewModels/DashboardViewModel.swift` | Add `positionStats: [PositionStats]`, compute in `loadData()` |
| `ViewModels/SessionDetailViewModel.swift` | Add `positionStats: [PositionStats]` computed |
| `Views/Dashboard/DashboardView.swift` | Add "Position Breakdown" section: horizontal scroll of `PositionStatsCardView` (only if any position data exists) |
| `Views/History/SessionDetailView.swift` | Add "Position Breakdown" section per session |
| `Views/Session/ActiveSessionView.swift` | Show position badge on recent hands (if not .unknown) |

### Test Files
- `PokerStatsTests/PositionStatsTests.swift` — Test `statsByPosition`, `vpip(hands:position:)`, `.unknown` excluded, worked example: 5 BTN hands with 4 raises = 80% PFR
- Update `PokerStatsTests/TestHelpers.swift` — Add `position` param to factory functions, add `raiseFromPosition(_:number:result:)` helper

### Manual Test Steps
1. Tap "Log Hand" → first step is now "Your Position" with 6 buttons
2. Tap a position (e.g., BTN) → advances to preflop step as before
3. Tap "Skip" → uses .unknown, advances to preflop
4. Fold path: position + fold = 2 taps (still fast)
5. Dashboard shows "Position Breakdown" with per-position VPIP/PFR
6. Session Detail shows position breakdown for that session
7. Active Session recent hands show position badges
8. Old hands (with .unknown) don't appear in position breakdown

---

## Verification After Each Phase

After implementing each phase:
1. `xcodegen generate` to regenerate project if new files/targets were added
2. Build: `xcodebuild build -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
3. Test: `xcodebuild test -scheme PokerStats -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
4. All existing tests must continue to pass
5. Run through manual test steps listed above
6. Fix any issues before proceeding to next phase
7. Once the phase builds and tests pass, suggest a commit message to the user (do NOT run git add, git commit, git push, or any git commands — only provide the message text)

### Suggested Commit Messages
- **Phase 1**: `feat: add dark theme design system with range bars, help icons, and play style labels`
- **Phase 2**: `feat: redesign dashboard with play style radar chart, 2-col stat grid, and circular gauges`
- **Phase 3**: `feat: add Trends tab with bankroll, VPIP/PFR, day-of-week, and P&L distribution charts`
- **Phase 4**: `feat: add tilt/energy/focus tracker with mental correlation insights`
- **Phase 5**: `feat: add Live Activities for active sessions and home screen widget`
- **Phase 6**: `feat: add Leak Finder with coaching insights and stat analysis`
- **Phase 7**: `feat: add position tracking in hand logger with position-based stat breakdowns`

**IMPORTANT**: NEVER run git add, git commit, git push, or any other git commands. Do NOT add, commit, or update anything in GitHub. Only suggest the commit message text for the user to run manually.
