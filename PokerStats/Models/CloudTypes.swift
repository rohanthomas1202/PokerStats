import Foundation

// MARK: - Backup Payload

struct BackupPayload: Codable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String
    let sessions: [SessionDTO]
    let settings: SettingsDTO?

    static let currentSchemaVersion = 1
}

// MARK: - Session DTO

struct SessionDTO: Codable, Sendable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let location: String
    let gameType: String
    let stakes: String
    let notes: String
    let status: String
    let buyIn: Double
    let rebuys: Double
    let addOns: Double
    let cashOut: Double
    let tipRake: Double
    let tiltLevel: Int?
    let energyLevel: Int?
    let focusLevel: Int?
    let tableConfigJson: String?
    let hands: [HandDTO]
}

// MARK: - Hand DTO

struct HandDTO: Codable, Sendable {
    let id: UUID
    let handNumber: Int
    let timestamp: Date
    let preflopAction: String
    let faced3Bet: Bool
    let threeBetResponse: String?
    let postflopResult: String?
    let didCBet: Bool?
    let notes: String
    let position: String
}

// MARK: - Settings DTO

struct SettingsDTO: Codable, Sendable {
    let id: UUID
    let defaultGameType: String
    let defaultStakes: String
    let defaultBuyIn: Double
    let currency: String
}

// MARK: - Backup Metadata (from Supabase)

struct BackupMetadata: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let storagePath: String
    let fileSizeBytes: Int64
    let schemaVersion: Int
    let sessionCount: Int
    let handCount: Int
    let createdAt: Date

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Model ↔ DTO Mapping

extension Session {
    func toDTO() -> SessionDTO {
        let tableConfigJsonString: String?
        if let data = tableConfigData {
            tableConfigJsonString = String(data: data, encoding: .utf8)
        } else {
            tableConfigJsonString = nil
        }

        return SessionDTO(
            id: id,
            startTime: startTime,
            endTime: endTime,
            location: location,
            gameType: gameType.rawValue,
            stakes: stakes,
            notes: notes,
            status: statusRaw,
            buyIn: buyIn,
            rebuys: rebuys,
            addOns: addOns,
            cashOut: cashOut,
            tipRake: tipRake,
            tiltLevel: tiltLevel,
            energyLevel: energyLevel,
            focusLevel: focusLevel,
            tableConfigJson: tableConfigJsonString,
            hands: hands.map { $0.toDTO() }
        )
    }

    static func fromDTO(_ dto: SessionDTO) -> Session {
        let session = Session(
            id: dto.id,
            startTime: dto.startTime,
            endTime: dto.endTime,
            location: dto.location,
            gameType: GameType(rawValue: dto.gameType) ?? .cash,
            stakes: dto.stakes,
            notes: dto.notes,
            status: SessionStatus(rawValue: dto.status) ?? .completed,
            buyIn: dto.buyIn,
            rebuys: dto.rebuys,
            addOns: dto.addOns,
            cashOut: dto.cashOut,
            tipRake: dto.tipRake
        )
        session.tiltLevel = dto.tiltLevel
        session.energyLevel = dto.energyLevel
        session.focusLevel = dto.focusLevel

        if let jsonString = dto.tableConfigJson {
            session.tableConfigData = jsonString.data(using: .utf8)
        }

        return session
    }
}

extension Hand {
    func toDTO() -> HandDTO {
        HandDTO(
            id: id,
            handNumber: handNumber,
            timestamp: timestamp,
            preflopAction: preflopAction.rawValue,
            faced3Bet: faced3Bet,
            threeBetResponse: threeBetResponse?.rawValue,
            postflopResult: postflopResult?.rawValue,
            didCBet: didCBet,
            notes: notes,
            position: position.rawValue
        )
    }

    static func fromDTO(_ dto: HandDTO) -> Hand {
        Hand(
            id: dto.id,
            handNumber: dto.handNumber,
            timestamp: dto.timestamp,
            preflopAction: PreflopAction(rawValue: dto.preflopAction) ?? .fold,
            faced3Bet: dto.faced3Bet,
            threeBetResponse: dto.threeBetResponse.flatMap { ThreeBetResponse(rawValue: $0) },
            postflopResult: dto.postflopResult.flatMap { PostflopResult(rawValue: $0) },
            didCBet: dto.didCBet,
            notes: dto.notes,
            position: SeatPosition(rawValue: dto.position) ?? .unknown
        )
    }
}

extension Settings {
    func toDTO() -> SettingsDTO {
        SettingsDTO(
            id: id,
            defaultGameType: defaultGameType.rawValue,
            defaultStakes: defaultStakes,
            defaultBuyIn: defaultBuyIn,
            currency: currency
        )
    }

    static func fromDTO(_ dto: SettingsDTO) -> Settings {
        Settings(
            id: dto.id,
            defaultGameType: GameType(rawValue: dto.defaultGameType) ?? .cash,
            defaultStakes: dto.defaultStakes,
            defaultBuyIn: dto.defaultBuyIn,
            currency: dto.currency
        )
    }
}
