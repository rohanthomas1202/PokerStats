import Foundation
import PostgREST
import Storage
import SwiftData

@MainActor
final class BackupService {
    private let client: SupabaseClient
    private let authService: AuthService
    private let modelContext: ModelContext
    private let owner: LocalDataOwner

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

    init(
        authService: AuthService,
        modelContext: ModelContext,
        client: SupabaseClient = .shared,
        owner: LocalDataOwner = .standard
    ) {
        self.authService = authService
        self.modelContext = modelContext
        self.client = client
        self.owner = owner
    }

    // MARK: - Create & Upload Backup

    func createAndUploadBackup() async throws -> BackupMetadata {
        guard authService.isAuthenticated,
              let userId = authService.userId else {
            throw BackupError.notAuthenticated
        }
        // Another account's data is never uploaded without the user's choice (#69).
        guard owner.allowsUpload(for: userId) else {
            throw BackupError.dataFromAnotherAccount
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
        let storagePath = "\(userId.uuidString.lowercased())/\(timestamp)_v\(BackupPayload.currentSchemaVersion).json.gz"

        // 6. Upload to storage
        try await client.storage.from("backups").upload(
            storagePath,
            data: compressedData,
            options: FileOptions(contentType: "application/gzip", upsert: true)
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

        let metadataArray: [BackupMetadata] = try await client.database
            .from("backup_metadata")
            .insert(metadataBody, returning: .representation)
            .execute()
            .value
        guard let metadata = metadataArray.first else {
            throw BackupError.metadataCreationFailed
        }

        // 9. Update profile.last_backup_at
        struct ProfileUpdate: Encodable, Sendable {
            let lastBackupAt: Date
        }

        _ = try? await client.database
            .from("profiles")
            .update(ProfileUpdate(lastBackupAt: .now))
            .eq("id", value: userId.uuidString)
            .execute()

        // 10. Data with no owner yet now belongs to this account.
        if owner.ownerId == nil {
            owner.adopt(userId)
        }

        // 11. Enforce retention
        try await enforceRetention(userId: userId)

        return metadata
    }

    // MARK: - List Backups

    func listBackups() async throws -> [BackupMetadata] {
        guard let userId = authService.userId else {
            throw BackupError.notAuthenticated
        }

        return try await client.database
            .from("backup_metadata")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(10)
            .execute()
            .value
    }

    // MARK: - Download Backup

    func downloadBackup(metadata: BackupMetadata) async throws -> BackupPayload {
        let compressedData = try await client.storage.from("backups").download(path: metadata.storagePath)

        let jsonData = try decompress(compressedData)
        let payload = try decoder.decode(BackupPayload.self, from: jsonData)

        // Validate schema version
        if payload.schemaVersion > BackupPayload.currentSchemaVersion {
            throw BackupError.schemaVersionTooNew(payload.schemaVersion)
        }

        return payload
    }

    // MARK: - Restore Backup

    /// Manual restore (Settings). Auto-restore goes through `AutoRestore`,
    /// which uses `LocalDataRestorer.restoreIfStoreEmpty`.
    /// Validates first, then deletes and inserts in one save, rolling back on error.
    /// The restored data is the signed-in account's, so that account owns it.
    func restoreBackup(_ payload: BackupPayload) throws {
        try LocalDataRestorer(modelContext: modelContext).restore(payload)
        if let userId = authService.userId {
            owner.adopt(userId)
        }
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

    private func enforceRetention(userId: UUID, keep: Int = 5) async throws {
        let backups = try await listBackups()

        guard backups.count > keep else { return }

        let toDelete = Array(backups.dropFirst(keep))
        for backup in toDelete {
            // Delete storage object
            _ = try? await client.storage.from("backups").remove(paths: [backup.storagePath])

            // Delete metadata row
            _ = try? await client.database
                .from("backup_metadata")
                .delete()
                .eq("id", value: backup.id.uuidString)
                .execute()
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
    /// The local data belongs to a different account (#69).
    case dataFromAnotherAccount

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
        case .dataFromAnotherAccount:
            "The local data belongs to a different account."
        }
    }
}
