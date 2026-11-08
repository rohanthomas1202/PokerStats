import Foundation

// Full-row fields from the app's models, for a create and for the first-sync
// upload (design 7.1). Nothing calls these while `SyncFeature.isEnabled` is
// false. `logging_device_id` and `deleted_at` wait for #85's model fields.

extension SyncSessionFields {
    /// Throws when `tableConfigData` is not a JSON object, rather than sending
    /// `table_config` as null and wiping the server's copy.
    init(creating session: Session) throws {
        let tableConfig = try session.tableConfigData.map {
            try JSONDecoder().decode([String: SyncJSON].self, from: $0)
        }
        self.init(
            startTime: session.startTime,
            endTime: .some(session.endTime),
            location: session.location,
            stakes: session.stakes,
            notes: session.notes,
            gameType: session.gameType,
            status: session.status,
            buyIn: session.buyIn,
            rebuys: session.rebuys,
            addOns: session.addOns,
            cashOut: session.cashOut,
            tipRake: session.tipRake,
            tiltLevel: .some(session.tiltLevel),
            energyLevel: .some(session.energyLevel),
            focusLevel: .some(session.focusLevel),
            // A JSON object, not the string the backup format uses.
            tableConfig: .some(tableConfig)
        )
    }
}

extension SyncHandFields {
    /// Nil for a hand with no session, which has no `session_id` to send.
    init?(creating hand: Hand) {
        guard let sessionId = hand.session?.id else { return nil }
        self = .create(
            sessionId: sessionId,
            handNumber: hand.handNumber,
            playedAt: hand.timestamp,
            preflopAction: hand.preflopAction,
            faced3Bet: hand.faced3Bet,
            position: hand.position,
            threeBetResponse: .some(hand.threeBetResponse),
            postflopResult: .some(hand.postflopResult),
            didCBet: .some(hand.didCBet),
            notes: hand.notes
        )
    }
}

extension SyncSettingsFields {
    init(_ settings: Settings) {
        self.init(
            defaultGameType: settings.defaultGameType,
            defaultStakes: settings.defaultStakes,
            defaultBuyIn: settings.defaultBuyIn,
            currency: settings.currency
        )
    }
}
