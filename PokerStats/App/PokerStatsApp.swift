import SwiftUI
import SwiftData

@main
struct PokerStatsApp: App {
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var cloudStatusMessage: String?

    init() {
        do {
            container = try AppGroupContainer.createSharedModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(authService)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--seed-screenshot-data") {
                        let context = container.mainContext
                        let count = (try? context.fetchCount(FetchDescriptor<Session>())) ?? 0
                        if count == 0 {
                            DataSeeder.seed(into: context)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if let message = cloudStatusMessage ?? authService.backupStatus {
                        Text(message)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: cloudStatusMessage)
                .animation(.easeInOut, value: authService.backupStatus)
                .onAppear {
                    if !ProcessInfo.processInfo.arguments.contains("--seed-screenshot-data") {
                        authService.initialize()
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        autoRestoreIfEmpty()
                    }
                }
        }
        .modelContainer(container)
    }

    private func autoRestoreIfEmpty() {
        let context = container.mainContext
        let sessionCount = (try? context.fetchCount(FetchDescriptor<Session>())) ?? 0
        guard sessionCount == 0 else { return }

        let backupService = BackupService(authService: authService, modelContext: context)
        Task { @MainActor in
            cloudStatusMessage = "Restoring from cloud..."
            do {
                let backups = try await backupService.listBackups()
                guard let latest = backups.first else {
                    cloudStatusMessage = "No backups found"
                    try? await Task.sleep(for: .seconds(2))
                    cloudStatusMessage = nil
                    return
                }
                let payload = try await backupService.downloadBackup(metadata: latest)
                try backupService.restoreBackup(payload)
                cloudStatusMessage = "Restored \(payload.sessions.count) sessions"
            } catch {
                cloudStatusMessage = "Restore failed: \(error.localizedDescription)"
            }
            try? await Task.sleep(for: .seconds(3))
            cloudStatusMessage = nil
        }
    }
}
