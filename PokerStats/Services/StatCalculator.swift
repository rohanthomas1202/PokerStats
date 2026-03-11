import Foundation

/// Pure-function stat calculator. All methods are static and take arrays of Hand objects.
/// No side effects, no persistence, no state. Designed for easy unit testing.
enum StatCalculator {

    // MARK: - Hand-Level Stats

    /// VPIP: % of hands where player voluntarily put money in pot preflop.
    /// Returns nil if no hands.
    static func vpip(hands: [Hand]) -> Double? {
        guard !hands.isEmpty else { return nil }
        let count = hands.filter(\.voluntarilyPutMoneyIn).count
        return Double(count) / Double(hands.count)
    }

    /// PFR: % of hands where player raised preflop.
    /// Returns nil if no hands.
    static func pfr(hands: [Hand]) -> Double? {
        guard !hands.isEmpty else { return nil }
        let count = hands.filter(\.raisedPreflop).count
        return Double(count) / Double(hands.count)
    }

    /// Fold to 3-Bet %: Of hands where hero raised and faced a 3-bet, how often folded.
    /// Returns nil if never faced a 3-bet.
    static func foldTo3BetPercent(hands: [Hand]) -> Double? {
        let faced = hands.filter { $0.faced3Bet }
        guard !faced.isEmpty else { return nil }
        let folded = faced.filter { $0.threeBetResponse == .folded }.count
        return Double(folded) / Double(faced.count)
    }

    /// C-Bet %: Of hands where hero raised preflop and saw flop, how often bet flop.
    /// Returns nil if no c-bet opportunities.
    static func cBetPercent(hands: [Hand]) -> Double? {
        let opportunities = hands.filter(\.hadCBetOpportunity)
        guard !opportunities.isEmpty else { return nil }
        let cBets = opportunities.filter { $0.didCBet == true }.count
        return Double(cBets) / Double(opportunities.count)
    }

    /// WTSD %: Of hands that saw the flop, how often reached showdown.
    /// Returns nil if no hands saw the flop.
    static func wtsdPercent(hands: [Hand]) -> Double? {
        let sawFlop = hands.filter(\.sawFlop)
        guard !sawFlop.isEmpty else { return nil }
        let showdown = sawFlop.filter(\.wentToShowdown).count
        return Double(showdown) / Double(sawFlop.count)
    }

    /// W$SD %: Of showdown hands, how often won.
    /// Returns nil if no showdowns.
    static func wsdPercent(hands: [Hand]) -> Double? {
        let showdowns = hands.filter(\.wentToShowdown)
        guard !showdowns.isEmpty else { return nil }
        let won = showdowns.filter(\.wonAtShowdown).count
        return Double(won) / Double(showdowns.count)
    }

    /// Count of hands folded preflop.
    static func handsFolded(hands: [Hand]) -> Int {
        hands.filter(\.foldedPreflop).count
    }

    // MARK: - Position-Filtered Stats

    /// VPIP filtered by position. Returns nil if no hands at that position.
    static func vpip(hands: [Hand], position: SeatPosition) -> Double? {
        let filtered = hands.filter { $0.position == position }
        return vpip(hands: filtered)
    }

    /// PFR filtered by position. Returns nil if no hands at that position.
    static func pfr(hands: [Hand], position: SeatPosition) -> Double? {
        let filtered = hands.filter { $0.position == position }
        return pfr(hands: filtered)
    }

    /// Compute stats grouped by position, excluding .unknown.
    static func statsByPosition(hands: [Hand]) -> [PositionStats] {
        SeatPosition.allPlayable.compactMap { position in
            let positionHands = hands.filter { $0.position == position }
            guard !positionHands.isEmpty else { return nil }
            return PositionStats(
                position: position,
                handCount: positionHands.count,
                vpip: vpip(hands: positionHands),
                pfr: pfr(hands: positionHands)
            )
        }
    }

    // MARK: - Session-Level Stats

    /// Compute all stats from an array of hands and sessions.
    static func computeAll(hands: [Hand], sessions: [Session]) -> ComputedStats {
        let completedSessions = sessions.filter { $0.status == .completed }

        let totalProfit = completedSessions.reduce(0.0) { $0 + $1.netProfit }
        let totalHours = completedSessions.reduce(0.0) { $0 + $1.durationHours }
        let sessionsPlayed = completedSessions.count

        let avgProfit: Double? = sessionsPlayed > 0
            ? totalProfit / Double(sessionsPlayed)
            : nil

        let hourlyRate: Double? = totalHours > 0.01
            ? totalProfit / totalHours
            : nil

        return ComputedStats(
            totalHands: hands.count,
            handsFolded: handsFolded(hands: hands),
            vpip: vpip(hands: hands),
            pfr: pfr(hands: hands),
            foldTo3BetPercent: foldTo3BetPercent(hands: hands),
            cBetPercent: cBetPercent(hands: hands),
            wtsdPercent: wtsdPercent(hands: hands),
            wsdPercent: wsdPercent(hands: hands),
            totalProfit: totalProfit,
            sessionsPlayed: sessionsPlayed,
            averageProfitPerSession: avgProfit,
            hourlyRate: hourlyRate,
            totalHoursPlayed: totalHours
        )
    }

    /// Compute stats for a single session's hands.
    static func computeSessionStats(session: Session) -> ComputedStats {
        computeAll(hands: session.hands, sessions: [session])
    }
}
