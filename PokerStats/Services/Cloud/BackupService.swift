import Foundation
import SwiftData

@MainActor
final class BackupService {
    private let client = SupabaseClient.shared
    private let authService: AuthService
    private let modelContext: ModelContext

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(authService: AuthService, modelContext: ModelContext) {
        self.authService = authService
        self.modelContext = modelContext
    }

    // MARK: - Create & Upload Backup

    func createAndUploadBackup() async throws -> BackupMetadata {
        guard authService.isAuthenticated,
              let userId = authService.userId else {
            throw BackupError.notAuthenticated
        }

        // 1. Fetch all local data
        let sessions = try fetchAllSessions()
        let settings = try fetchSettings()

        // 2. Map to DTOs
        let sessionDTOs = sessions.map { $0.toDTO() }
        let settingsDTO = settings?.toDTO()

        let payload = BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            createdAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            sessions: sessionDTOs,
            settings: settingsDTO
        )

        // 3. Encode to JSON
        let jsonData = try encoder.encode(payload)

        // 4. Compress
        let compressedData = try compress(jsonData)

        // 5. Generate storage path
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let storagePath = "\(userId.uuidString)/\(timestamp)_v\(BackupPayload.currentSchemaVersion).json.gz"

        // 6. Upload to storage
        try await client.uploadFile(
            bucket: "backups",
            path: storagePath,
            data: compressedData,
            contentType: "application/gzip"
        )

        // 7. Count hands
        let handCount = sessions.reduce(0) { $0 + $1.hands.count }

        // 8. Insert backup_metadata row
        struct MetadataInsert: Encodable, Sendable {
            let userId: UUID
            let storagePath: String
            let fileSizeBytes: Int64
            let schemaVersion: Int
            let sessionCount: Int
            let handCount: Int
        }

        let metadataBody = MetadataInsert(
            userId: userId,
            storagePath: storagePath,
            fileSizeBytes: Int64(compressedData.count),
            schemaVersion: BackupPayload.currentSchemaVersion,
            sessionCount: sessions.count,
            handCount: handCount
        )

        let responseData = try await client.request(
            endpoint: "/rest/v1/backup_metadata",
            method: .post,
            body: metadataBody,
            headers: ["Prefer": "return=representation"]
        )

        let metadataArray = try decoder.decode([BackupMetadata].self, from: responseData)
        guard let metadata = metadataArray.first else {
            throw BackupError.metadataCreationFailed
        }

        // 9. Update profile.last_backup_at
        struct ProfileUpdate: Encodable, Sendable {
            let lastBackupAt: Date
        }

        _ = try? await client.request(
            endpoint: "/rest/v1/profiles",
            method: .patch,
            body: ProfileUpdate(lastBackupAt: .now),
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userId.uuidString)")],
            headers: ["Prefer": "return=minimal"]
        )

        // 10. Enforce retention
        try await enforceRetention(userId: userId)

        return metadata
    }

    // MARK: - List Backups

    func listBackups() async throws -> [BackupMetadata] {
        guard let userId = authService.userId else {
            throw BackupError.notAuthenticated
        }

        let data = try await client.request(
            endpoint: "/rest/v1/backup_metadata",
            method: .get,
            queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "10")
            ]
        )

        return try decoder.decode([BackupMetadata].self, from: data)
    }

    // MARK: - Download Backup

    func downloadBackup(metadata: BackupMetadata) async throws -> BackupPayload {
        let compressedData = try await client.downloadFile(
            bucket: "backups",
            path: metadata.storagePath
        )

        let jsonData = try decompress(compressedData)
        let payload = try decoder.decode(BackupPayload.self, from: jsonData)

        // Validate schema version
        if payload.schemaVersion > BackupPayload.currentSchemaVersion {
            throw BackupError.schemaVersionTooNew(payload.schemaVersion)
        }

        return payload
    }

    // MARK: - Restore Backup

    func restoreBackup(_ payload: BackupPayload) throws {
        // 1. Delete all existing local data
        try deleteAllLocalData()

        // 2. Recreate sessions with hands
        for sessionDTO in payload.sessions {
            let session = Session.fromDTO(sessionDTO)
            modelContext.insert(session)

            for handDTO in sessionDTO.hands {
                let hand = Hand.fromDTO(handDTO)
                hand.session = session
                modelContext.insert(hand)
            }
        }

        // 3. Recreate settings
        if let settingsDTO = payload.settings {
            let settings = Settings.fromDTO(settingsDTO)
            modelContext.insert(settings)
        }

        // 4. Save
        try modelContext.save()
    }

    // MARK: - Private Helpers

    private func fetchAllSessions() throws -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSettings() throws -> Settings? {
        let descriptor = FetchDescriptor<Settings>()
        return try modelContext.fetch(descriptor).first
    }

    private func deleteAllLocalData() throws {
        // Delete all hands first (even though cascade should handle it)
        let handDescriptor = FetchDescriptor<Hand>()
        let hands = try modelContext.fetch(handDescriptor)
        for hand in hands {
            modelContext.delete(hand)
        }

        // Delete all sessions
        let sessionDescriptor = FetchDescriptor<Session>()
        let sessions = try modelContext.fetch(sessionDescriptor)
        for session in sessions {
            modelContext.delete(session)
        }

        // Delete all settings
        let settingsDescriptor = FetchDescriptor<Settings>()
        let settings = try modelContext.fetch(settingsDescriptor)
        for setting in settings {
            modelContext.delete(setting)
        }

        try modelContext.save()
    }

    private func enforceRetention(userId: UUID, keep: Int = 5) async throws {
        let backups = try await listBackups()

        guard backups.count > keep else { return }

        let toDelete = Array(backups.dropFirst(keep))
        for backup in toDelete {
            // Delete storage object
            try? await client.deleteFile(bucket: "backups", path: backup.storagePath)

            // Delete metadata row
            _ = try? await client.request(
                endpoint: "/rest/v1/backup_metadata",
                method: .delete,
                queryItems: [URLQueryItem(name: "id", value: "eq.\(backup.id.uuidString)")]
            )
        }
    }

    // MARK: - Compression

    private func compress(_ data: Data) throws -> Data {
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data else {
            throw BackupError.compressionFailed
        }
        return compressed
    }

    private func decompress(_ data: Data) throws -> Data {
        guard let decompressed = try? (data as NSData).decompressed(using: .zlib) as Data else {
            throw BackupError.decompressionFailed
        }
        return decompressed
    }
}

// MARK: - Errors

enum BackupError: LocalizedError, Sendable {
    case notAuthenticated
    case compressionFailed
    case decompressionFailed
    case schemaVersionTooNew(Int)
    case metadataCreationFailed
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Sign in to use cloud backup."
        case .compressionFailed:
            "Failed to compress backup data."
        case .decompressionFailed:
            "Failed to decompress backup data."
        case .schemaVersionTooNew(let version):
            "This backup requires a newer app version (schema v\(version)). Please update PokerStats."
        case .metadataCreationFailed:
            "Failed to save backup metadata."
        case .restoreFailed(let message):
            "Restore failed: \(message)"
        }
    }
}
