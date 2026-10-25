import Foundation
import SwiftData
import Testing
@testable import PokerStats

/// Request shapes of the backup calls made through supabase-swift (Storage
/// and PostgREST), and PostgREST `timestamptz` decoding (#133).
@Suite("Backup Service Request Tests")
@MainActor
struct BackupServiceRequestTests {
    private nonisolated static let userPath = TestUser.id.uuidString.lowercased()
    /// 2026-10-25 21:50:00 UTC.
    private nonisolated static let createdAt: TimeInterval = 1_792_965_000

    /// A `backup_metadata` row as PostgREST returns it.
    private nonisolated static func row(id: UUID = UUID(), path: String, createdAt: String) -> String {
        """
        {"id":"\(id.uuidString)","user_id":"\(TestUser.id.uuidString)","storage_path":"\(path)",
         "file_size_bytes":123,"schema_version":1,"session_count":0,"hand_count":0,
         "created_at":"\(createdAt)"}
        """
    }

    private let container: ModelContainer

    init() throws {
        container = try TestHelpers.createContainer()
    }

    /// A backup service for a signed-in `TestUser` whose requests go to `respond`.
    private func service(
        server: FakeServer,
        respond: @escaping @Sendable (SeenRequest, Int) async throws -> FakeReply
    ) -> BackupService {
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let client = testClient(storage, server: server, respond: respond)
        let auth = AuthService(client: client)
        auth.restoreSession()
        return BackupService(authService: auth, modelContext: container.mainContext, client: client)
    }

    @Test func createAndUploadBackup_sendsUploadMetadataProfileAndRetention() async throws {
        let server = FakeServer()
        // Seven stored backups, newest first: the two oldest go.
        let listed = (1...7).map { Self.row(path: "\(Self.userPath)/old-\($0).json.gz", createdAt: "2026-10-2\($0)T10:00:00+00:00") }
        let sut = service(server: server) { request, _ in
            switch (request.method, request.path) {
            case ("POST", let path) where path.hasPrefix("/storage/v1/object/backups/"):
                return .status(200, #"{"Key":"backups/x","Id":"1"}"#)
            case ("POST", "/rest/v1/backup_metadata"):
                return .status(201, "[\(Self.row(path: "new", createdAt: "2026-10-25T21:50:00.123456+00:00"))]")
            case ("GET", "/rest/v1/backup_metadata"):
                return .status(200, "[\(listed.joined(separator: ","))]")
            case ("DELETE", "/storage/v1/object/backups"):
                return .status(200, "[]")
            default:
                return .status(204, "")
            }
        }

        let metadata = try await sut.createAndUploadBackup()

        #expect(abs(metadata.createdAt.timeIntervalSince1970 - (Self.createdAt + 0.123456)) < 0.001)
        let requests = server.requests
        #expect(requests.allSatisfy { $0.header("Authorization") == "Bearer fresh-access" })
        #expect(requests.allSatisfy { $0.header("apikey") == "anon-key" })
        #expect(server.refreshCount == 0)

        // 1. Upload to the user's folder in the backups bucket.
        let upload = try #require(requests.first)
        let uploadPath = upload.path.removingPercentEncoding ?? upload.path
        #expect(upload.method == "POST")
        #expect(uploadPath.hasPrefix("/storage/v1/object/backups/\(Self.userPath)/"))
        #expect(uploadPath.hasSuffix("_v\(BackupPayload.currentSchemaVersion).json.gz"))
        #expect(upload.header("x-upsert") == "true")
        #expect(upload.header("Content-Type")?.hasPrefix("multipart/form-data") == true)
        let uploadBody = String(decoding: upload.body ?? Data(), as: UTF8.self)
        #expect(uploadBody.contains("Content-Type: application/gzip"))

        // 2. backup_metadata row, snake_case, returning the row.
        let insert = try #require(requests.first { $0.method == "POST" && $0.path == "/rest/v1/backup_metadata" })
        #expect(insert.header("Prefer") == "return=representation")
        let row = try #require(insert.json)
        #expect(row["user_id"] as? String == TestUser.id.uuidString)
        #expect(row["storage_path"] as? String == String(uploadPath.dropFirst("/storage/v1/object/backups/".count)))
        #expect((row["file_size_bytes"] as? Int ?? 0) > 0)
        #expect(row["schema_version"] as? Int == BackupPayload.currentSchemaVersion)
        #expect(row["session_count"] as? Int == 0)
        #expect(row["hand_count"] as? Int == 0)
        #expect(Set(row.keys) == ["user_id", "storage_path", "file_size_bytes", "schema_version", "session_count", "hand_count"])

        // 3. profiles.last_backup_at for this user.
        let profile = try #require(requests.first { $0.path == "/rest/v1/profiles" })
        #expect(profile.method == "PATCH")
        #expect(profile.queryItems["id"] == "eq.\(TestUser.id.uuidString)")
        #expect(profile.json.map { Array($0.keys) } == ["last_backup_at"])
        #expect((profile.json?["last_backup_at"] as? String)?.isEmpty == false)

        // 4. Retention: list newest first, then remove the two oldest files and rows.
        let list = try #require(requests.first { $0.method == "GET" && $0.path == "/rest/v1/backup_metadata" })
        #expect(list.queryItems["select"] == "*")
        #expect(list.queryItems["user_id"] == "eq.\(TestUser.id.uuidString)")
        #expect(list.queryItems["order"] == "created_at.desc.nullslast")
        #expect(list.queryItems["limit"] == "10")

        let removes = requests.filter { $0.method == "DELETE" && $0.path == "/storage/v1/object/backups" }
        #expect(removes.map { $0.json?["prefixes"] as? [String] } == [
            ["\(Self.userPath)/old-6.json.gz"],
            ["\(Self.userPath)/old-7.json.gz"],
        ])
        let rowDeletes = requests.filter { $0.method == "DELETE" && $0.path == "/rest/v1/backup_metadata" }
        #expect(rowDeletes.count == 2)
        #expect(rowDeletes.allSatisfy { $0.queryItems["id"]?.hasPrefix("eq.") == true })
    }

    /// PostgREST sends `timestamptz` with or without fractional seconds;
    /// both decode (the old client's `.iso8601` rejected fractions).
    @Test func listBackups_decodesTimestampsWithAndWithoutFractions() async throws {
        let server = FakeServer()
        let body = "[" + [
            Self.row(path: "a", createdAt: "2026-10-25T21:50:00.123456+00:00"),
            Self.row(path: "b", createdAt: "2026-10-25T21:50:00+00:00"),
        ].joined(separator: ",") + "]"
        let sut = service(server: server) { _, _ in .status(200, body) }

        let backups = try await sut.listBackups()

        #expect(backups.map(\.storagePath) == ["a", "b"])
        #expect(abs(backups[0].createdAt.timeIntervalSince1970 - (Self.createdAt + 0.123456)) < 0.001)
        #expect(backups[1].createdAt.timeIntervalSince1970 == Self.createdAt)
        #expect(backups[0].fileSizeBytes == 123)
        #expect(backups[0].userId == TestUser.id)
    }

    @Test func downloadBackup_getsTheObject_andDecodesThePayload() async throws {
        let server = FakeServer()
        let payload = BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: Self.createdAt),
            appVersion: "1.0.0",
            sessions: [],
            settings: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let compressed = try (encoder.encode(payload) as NSData).compressed(using: .zlib) as Data
        let sut = service(server: server) { _, _ in .data(200, compressed) }
        let metadata = BackupMetadata(
            id: UUID(),
            userId: TestUser.id,
            storagePath: "\(Self.userPath)/b.json.gz",
            fileSizeBytes: Int64(compressed.count),
            schemaVersion: 1,
            sessionCount: 0,
            handCount: 0,
            createdAt: Date(timeIntervalSince1970: Self.createdAt)
        )

        let restored = try await sut.downloadBackup(metadata: metadata)

        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "GET")
        #expect(request.path == "/storage/v1/object/backups/\(Self.userPath)/b.json.gz")
        #expect(request.header("Authorization") == "Bearer fresh-access")
        #expect(restored.schemaVersion == payload.schemaVersion)
        #expect(restored.createdAt == payload.createdAt)
        #expect(restored.sessions.isEmpty)
    }
}
