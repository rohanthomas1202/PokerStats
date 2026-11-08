import Foundation
import SwiftData
import Testing
@testable import PokerStats

/// The app's stats checked against the shared golden fixtures in
/// shared/fixtures/stats (#235, #238). Each dataset's live rows are loaded into
/// an in-memory store and run through the code the screens use: the Dashboard,
/// Leak Finder and session screens' calculators, TrendCalculator and the
/// widget's `LifetimeSummary`. The output is compared field by field with the
/// dataset's `expected` block, numbers within a relative 1e-9 (the fixture
/// convention, finer than any displayed precision), so a changed expected
/// value fails. display.json is checked against the app's formatters.
/// Expects an en_US simulator, as display.json does.
@Suite("Stat fixtures")
@MainActor
struct StatFixtureTests {

    /// Every dataset in the test bundle's datasets folder.
    nonisolated static var datasetNames: [String] {
        (Bundle(for: FixtureBundle.self).urls(forResourcesWithExtension: "json", subdirectory: "datasets") ?? [])
            .map(\.lastPathComponent)
            .sorted()
    }

    @Test func bundle_hasEveryDataset() {
        let names = Set(Self.datasetNames)
        for name in [
            "core.json", "empty.json", "pl-distribution-boundary.json", "pl-distribution-wide.json",
            "short-sessions.json", "single-session.json", "tilt-levels.json",
        ] {
            #expect(names.contains(name), "\(name) is not in the test bundle")
        }
    }

    @Test(arguments: StatFixtureTests.datasetNames)
    func dataset_matchesExpected(_ name: String) throws {
        let fixture = try Fixture(dataset: name)
        let expected = try fixture.expected()
        let output = try fixture.appOutput()
        let problems = Fixture.diff(output, expected, at: "expected")
        #expect(problems.isEmpty, "\(name):\n\(problems.joined(separator: "\n"))")

        // Every completed session in a window lands in exactly one P/L bar
        // (Kate's Low 1 on PR #287).
        let trends = try #require(expected["trends"] as? [String: [String: Any]])
        for (window, values) in trends {
            let buckets = try #require(values["pl_distribution"] as? [[String: Any]])
            let total = buckets.compactMap { $0["count"] as? Int }.reduce(0, +)
            #expect(total == (values["session_count"] as? Int), "\(name) \(window)")
        }
    }

    /// The comparison is not vacuous: one changed expected value is reported.
    @Test func changedExpectedValue_fails() throws {
        let fixture = try Fixture(dataset: "core.json")
        var expected = try fixture.expected()
        let output = try fixture.appOutput()
        #expect(Fixture.diff(output, expected, at: "expected").isEmpty)
        var lifetime = try #require(expected["lifetime"] as? [String: Any])
        lifetime["vpip"] = NSNumber(value: 0.62)
        expected["lifetime"] = lifetime
        let problems = Fixture.diff(output, expected, at: "expected")
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("expected.lifetime.vpip:") == true)
    }

    @Test func leakRanges_matchDefinitions() throws {
        let definitions = try Fixture.load("definitions", subdirectory: nil)
        let ranges = try #require((definitions["leak_profiles"] as? [String: Any])?["ranges"])
        var app: [String: Any] = [:]
        for profile in ReferenceProfile.allCases {
            var stats: [String: Any] = [:]
            for (key, range) in profile.ranges {
                stats[Fixture.key(key)] = [
                    "ideal": [range.ideal.lowerBound, range.ideal.upperBound],
                    "acceptable": [range.acceptable.lowerBound, range.acceptable.upperBound],
                ]
            }
            app[Fixture.key(profile)] = stats
        }
        let problems = Fixture.diff(app, ranges, at: "leak_profiles.ranges")
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test func displayStrings_matchAppFormatters() throws {
        let display = try Fixture.load("display", subdirectory: nil)
        let cases = try #require(display["cases"] as? [[String: Any]])
        #expect(!cases.isEmpty)
        for item in cases {
            let format = try #require(item["format"] as? String)
            let value = item["value"] as? Double
            let shown: String
            switch format {
            case "percent": shown = ComputedStats.formatPercent(value)
            case "hourly_rate": shown = ComputedStats.formatHourlyRate(value)
            case "currency": shown = CurrencyFormatter.format(try #require(value))
            case "currency_signed", "widget_currency": shown = CurrencyFormatter.formatSigned(try #require(value))
            case "widget_hourly": shown = CurrencyFormatter.formatSigned(try #require(value), fractionDigits: 2)
            case "roi": shown = SessionDetailView.roiDisplay(netProfit: try #require(value), totalInvested: 1).text
            default:
                Issue.record("display.json uses unknown format \(format)")
                continue
            }
            #expect(shown == (item["expected"] as? String), "\(format)(\(String(describing: value)))")
        }
    }
}

private final class FixtureBundle {}

/// One dataset's live rows in an in-memory store, and the app's output for it
/// in the shape of the dataset's `expected` block.
@MainActor
private struct Fixture {
    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    let json: [String: Any]
    let container: ModelContainer
    let now: Date
    let timeZone: TimeZone
    /// Live sessions in row order.
    let sessions: [Session]

    var context: ModelContext { container.mainContext }

    init(dataset name: String) throws {
        let json = try Self.load((name as NSString).deletingPathExtension, subdirectory: "datasets")
        let zone: String = try Self.value(json, "time_zone")
        guard let timeZone = TimeZone(identifier: zone) else {
            throw Missing(description: "\(name): unknown time_zone")
        }
        let container = try TestHelpers.createContainer()
        let context = container.mainContext

        // Design 9.1: tombstoned rows, and hands of a tombstoned session, are not
        // inputs. The app hard-deletes, so they are simply not loaded.
        var byID: [String: Session] = [:]
        var sessions: [Session] = []
        let sessionRows: [[String: Any]] = try Self.value(json, "sessions")
        for row in sessionRows where row["deleted_at"] is NSNull {
            let id: String = try Self.value(row, "id")
            let endTime = try (row["end_time"] as? String).map { try Self.date($0) }
            let session = try Session(
                id: Self.uuid(id),
                startTime: Self.date(Self.value(row, "start_time")),
                endTime: endTime,
                location: Self.value(row, "location"),
                gameType: Self.enumValue(Self.value(row, "game_type")),
                stakes: Self.value(row, "stakes"),
                notes: Self.value(row, "notes"),
                buyIn: Self.value(row, "buy_in"),
                rebuys: Self.value(row, "rebuys"),
                addOns: Self.value(row, "add_ons"),
                cashOut: Self.value(row, "cash_out"),
                tipRake: Self.value(row, "tip_rake")
            )
            // The raw status, so an unknown one ("paused") decodes as the app does.
            session.statusRaw = try Self.value(row, "status")
            session.tiltLevel = row["tilt_level"] as? Int
            session.energyLevel = row["energy_level"] as? Int
            session.focusLevel = row["focus_level"] as? Int
            context.insert(session)
            byID[id] = session
            sessions.append(session)
        }
        var handCount = 0
        let handRows: [[String: Any]] = try Self.value(json, "hands")
        for row in handRows where row["deleted_at"] is NSNull {
            let sessionID: String = try Self.value(row, "session_id")
            guard let session = byID[sessionID] else { continue }
            let threeBetResponse: ThreeBetResponse? = try (row["three_bet_response"] as? String).map { try Self.enumValue($0) }
            let postflopResult: PostflopResult? = try (row["postflop_result"] as? String).map { try Self.enumValue($0) }
            let hand = try Hand(
                id: Self.uuid(Self.value(row, "id")),
                handNumber: Self.value(row, "hand_number"),
                timestamp: Self.date(Self.value(row, "played_at")),
                preflopAction: Self.enumValue(Self.value(row, "preflop_action")),
                faced3Bet: Self.value(row, "faced_3bet"),
                threeBetResponse: threeBetResponse,
                postflopResult: postflopResult,
                didCBet: row["did_cbet"] as? Bool,
                notes: Self.value(row, "notes"),
                position: Self.enumValue(Self.value(row, "position"))
            )
            hand.session = session
            context.insert(hand)
            handCount += 1
        }
        try context.save()
        guard sessions.reduce(0, { $0 + $1.hands.count }) == handCount else {
            throw Missing(description: "\(name): hands did not attach to their sessions")
        }
        self.json = json
        self.container = container
        self.now = try Self.date(Self.value(json, "now"))
        self.timeZone = timeZone
        self.sessions = sessions
    }

    /// The dataset's `expected` block, less the fields the app reads from the
    /// clock: an open session's duration runs to `.now` (Session.duration), not
    /// to the dataset's `now`, so its duration_hours and hourly_rate are not
    /// compared. No open session is completed, so no money stat reads the clock.
    func expected() throws -> [String: Any] {
        var expected: [String: Any] = try Self.value(json, "expected")
        let open = Set(sessions.filter { $0.endTime == nil }.map { $0.id.uuidString.lowercased() })
        let rows: [[String: Any]] = try Self.value(expected, "sessions")
        expected["sessions"] = rows.map { row in
            guard let id = row["id"] as? String, open.contains(id) else { return row }
            return row.filter { $0.key != "duration_hours" && $0.key != "hourly_rate" }
        }
        return expected
    }

    // MARK: - The app's output

    func appOutput() throws -> [String: Any] {
        let dashboard = DashboardViewModel()
        dashboard.loadData(from: context)
        let stats = dashboard.lifetimeStats

        var lifetime = Self.handStats(stats)
        lifetime["total_profit"] = stats.totalProfit
        lifetime["sessions_played"] = stats.sessionsPlayed
        lifetime["average_profit_per_session"] = Self.orNull(stats.averageProfitPerSession)
        lifetime["hourly_rate"] = Self.orNull(stats.hourlyRate)
        lifetime["total_hours_played"] = stats.totalHoursPlayed
        lifetime["fold_percent"] = Self.orNull(dashboard.foldPercent)
        lifetime["play_style"] = Self.orNull(dashboard.playStyle?.rawValue)

        let perSession: [[String: Any]] = sessions.map { session in
            let sessionStats = StatCalculator.computeSessionStats(session: session)
            var row = Self.handStats(sessionStats)
            row["id"] = session.id.uuidString.lowercased()
            row["counts_toward_money_stats"] = session.status == .completed
            row["net_profit"] = session.netProfit
            if session.endTime != nil {
                row["duration_hours"] = session.durationHours
                row["hourly_rate"] = Self.orNull(session.hourlyRate)
            }
            row["roi"] = Self.orNull(session.roi)
            // LeakFinderViewModel.sessionInsights needs 10 hands; fewer is null.
            if sessionStats.totalHands >= 10 {
                row["leak_finder"] = Self.leakFinder { LeakFinderViewModel.sessionInsights(session: session, profile: $0) }
            } else {
                row["leak_finder"] = NSNull()
            }
            return row
        }

        var insight: Any = NSNull()
        if let mental = dashboard.mentalInsight {
            insight = ["calm_rate": mental.calmRate, "tilted_rate": mental.tiltedRate] as [String: Double]
        }

        let leakViewModel = LeakFinderViewModel()
        leakViewModel.loadData(from: context)
        var lifetimeLeaks: Any = NSNull()
        if leakViewModel.hasEnoughData {
            lifetimeLeaks = Self.leakFinder { profile in
                leakViewModel.selectedProfile = profile
                leakViewModel.loadData(from: context)
                return leakViewModel.insights
            }
        }

        let trendOutput = try trends()
        let summary = LifetimeSummary.fetch(from: context)
        return [
            "lifetime": lifetime,
            "sessions": perSession,
            "positions": dashboard.positionStats.map {
                ["position": $0.position.rawValue, "hand_count": $0.handCount, "vpip": Self.orNull($0.vpip), "pfr": Self.orNull($0.pfr)] as [String: Any]
            },
            "trends": trendOutput,
            "mental_correlation": dashboard.mentalCorrelation.map {
                ["metric": $0.metricType.rawValue, "level": $0.level, "average_hourly_rate": $0.averageHourlyRate, "session_count": $0.sessionCount] as [String: Any]
            },
            "mental_insight": insight,
            "leak_finder": lifetimeLeaks,
            "widget": [
                "total_profit": summary.totalProfit,
                "sessions_played": summary.sessionsPlayed,
                "hourly_rate": Self.orNull(summary.hourlyRate),
                "current_streak": summary.currentStreak,
            ] as [String: Any],
        ]
    }

    /// Both windows, as TrendsViewModel.loadData builds them. The 30-day cutoff
    /// is the dataset's `now` minus 30 x 24 hours, since the app's cutoff reads
    /// the clock (the datasets cross no DST change, so both agree).
    private func trends() throws -> [String: Any] {
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startTime, order: .reverse)]))
        let hands = try context.fetch(FetchDescriptor<Hand>())
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        return [
            "all_time": window(sessions: sessions, hands: hands),
            "last_30_days": window(
                sessions: sessions.filter { $0.startTime >= cutoff },
                hands: hands.filter { $0.timestamp >= cutoff }
            ),
        ]
    }

    private func window(sessions: [Session], hands: [Hand]) -> [String: Any] {
        [
            "session_count": sessions.filter { $0.status == .completed }.count,
            "cumulative_bankroll": TrendCalculator.cumulativeBankroll(sessions: sessions).map {
                ["date": $0.date, "cumulative_profit": $0.cumulativeProfit, "session_index": $0.sessionIndex] as [String: Any]
            },
            "rolling_vpip_pfr": TrendCalculator.rollingVPIPPFR(hands: hands).map {
                ["hand_index": $0.handIndex, "vpip": $0.vpip, "pfr": $0.pfr] as [String: Any]
            },
            "profit_by_day_of_week": TrendCalculator.profitByDayOfWeek(sessions: inDeviceZone(sessions)).map {
                ["day_name": $0.dayName, "day_number": $0.dayNumber, "total_profit": $0.totalProfit, "session_count": $0.sessionCount] as [String: Any]
            },
            "pl_distribution": TrendCalculator.sessionPLDistribution(sessions: sessions).map {
                ["range_label": $0.rangeLabel, "lower_bound": $0.lowerBound, "upper_bound": $0.upperBound, "count": $0.count] as [String: Any]
            },
        ]
    }

    /// profitByDayOfWeek takes the weekday in the device's zone; the fixtures
    /// pin it to the dataset's `time_zone`. Copies of the sessions with each
    /// start moved by the difference between the two zones read, on the
    /// device, the weekday they have in `time_zone`.
    private func inDeviceZone(_ sessions: [Session]) -> [Session] {
        let device = Calendar.current.timeZone
        return sessions.map { session in
            let shift = timeZone.secondsFromGMT(for: session.startTime) - device.secondsFromGMT(for: session.startTime)
            let copy = Session(
                startTime: session.startTime.addingTimeInterval(TimeInterval(shift)),
                endTime: session.endTime,
                buyIn: session.buyIn,
                rebuys: session.rebuys,
                addOns: session.addOns,
                cashOut: session.cashOut
            )
            copy.statusRaw = session.statusRaw
            return copy
        }
    }

    private static func handStats(_ stats: ComputedStats) -> [String: Any] {
        [
            "total_hands": stats.totalHands,
            "hands_folded": stats.handsFolded,
            "vpip": orNull(stats.vpip),
            "pfr": orNull(stats.pfr),
            "fold_to_3bet": orNull(stats.foldTo3BetPercent),
            "cbet": orNull(stats.cBetPercent),
            "wtsd": orNull(stats.wtsdPercent),
            "wsd": orNull(stats.wsdPercent),
        ]
    }

    /// Ratings by stat and the overall rating, for each profile.
    private static func leakFinder(_ insights: (ReferenceProfile) -> [LeakInsight]) -> [String: Any] {
        var result: [String: Any] = [:]
        for profile in ReferenceProfile.allCases {
            let list = insights(profile)
            var ratings: [String: String] = [:]
            for insight in list { ratings[key(insight.statKey)] = insight.rating.rawValue }
            result[key(profile)] = ["ratings": ratings, "overall": LeakFinder.overallRating(from: list).rawValue] as [String: Any]
        }
        return result
    }

    nonisolated static func key(_ profile: ReferenceProfile) -> String {
        switch profile {
        case .fullRingCash: "full_ring"
        case .sixMaxCash: "six_max"
        }
    }

    nonisolated static func key(_ stat: StatKey) -> String {
        switch stat {
        case .vpip: "vpip"
        case .pfr: "pfr"
        case .cBet: "cbet"
        case .foldTo3Bet: "fold_to_3bet"
        case .wtsd: "wtsd"
        case .wsd: "wsd"
        }
    }

    private static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    // MARK: - Comparison

    /// Differences between the app's output and a fixture's JSON, as
    /// stats.test.ts reports them: numbers within a relative 1e-9, the same keys
    /// on both sides, and dates compared as instants.
    nonisolated static func diff(_ got: Any, _ want: Any, at path: String) -> [String] {
        let mismatch = ["\(path): got \(got), want \(want)"]
        switch want {
        case is NSNull:
            return got is NSNull ? [] : mismatch
        case let want as NSNumber where CFGetTypeID(want) == CFBooleanGetTypeID():
            return (got as? Bool) == want.boolValue ? [] : mismatch
        case let want as NSNumber:
            let number: Double? = (got as? Double) ?? (got as? Int).map(Double.init)
            guard let number else { return mismatch }
            let tolerance = 1e-9 * max(1, abs(want.doubleValue))
            return abs(number - want.doubleValue) <= tolerance ? [] : mismatch
        case let want as String:
            if let got = got as? Date {
                guard let wanted = try? date(want) else { return mismatch }
                return abs(got.timeIntervalSince(wanted)) < 0.001 ? [] : mismatch
            }
            return (got as? String) == want ? [] : mismatch
        case let want as [Any]:
            guard let got = got as? [Any], got.count == want.count else { return mismatch }
            return zip(got, want).enumerated().flatMap { i, pair in diff(pair.0, pair.1, at: "\(path)[\(i)]") }
        case let want as [String: Any]:
            guard let got = got as? [String: Any] else { return ["\(path): got \(got), want an object"] }
            return Set(want.keys).union(got.keys).sorted().flatMap { key -> [String] in
                guard let w = want[key] else { return ["\(path).\(key): unexpected"] }
                guard let g = got[key] else { return ["\(path).\(key): missing"] }
                return diff(g, w, at: "\(path).\(key)")
            }
        default:
            return ["\(path): unsupported fixture value \(want)"]
        }
    }

    // MARK: - JSON

    nonisolated static func load(_ name: String, subdirectory: String?) throws -> [String: Any] {
        guard let url = Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            throw Missing(description: "\(name).json is not in the test bundle")
        }
        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw Missing(description: "\(name).json is not an object")
        }
        return json
    }

    nonisolated static func value<T>(_ row: [String: Any], _ key: String) throws -> T {
        guard let value = row[key] as? T else { throw Missing(description: "\(key) is not a \(T.self)") }
        return value
    }

    nonisolated static func date(_ text: String) throws -> Date {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
        return try Date.ISO8601FormatStyle().parse(text)
    }

    nonisolated static func uuid(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text) else { throw Missing(description: "bad id \(text)") }
        return id
    }

    nonisolated static func enumValue<E: RawRepresentable>(_ raw: String) throws -> E where E.RawValue == String {
        guard let value = E(rawValue: raw) else { throw Missing(description: "unknown \(E.self) \(raw)") }
        return value
    }
}
