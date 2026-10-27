import SwiftUI
import SwiftData

@main
struct PokerStatsApp: App {
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var autoRestore = AutoRestoreViewModel()

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
                    if let message = autoRestore.message {
                        CloudStatusBanner(message: message, autoRestore: autoRestore)
                    } else if let message = authService.backupStatus {
                        CloudStatusBanner(message: message)
                    }
                }
                .animation(.easeInOut, value: autoRestore.status)
                .animation(.easeInOut, value: authService.backupStatus)
                .onAppear {
                    if !ProcessInfo.processInfo.arguments.contains("--seed-screenshot-data") {
                        authService.initialize()
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        autoRestoreIfEmpty()
                    } else {
                        autoRestore.dismiss()
                    }
                }
        }
        .modelContainer(container)
    }

    private func autoRestoreIfEmpty() {
        let context = container.mainContext
        let backupService = BackupService(authService: authService, modelContext: context)
        let restore = AutoRestore(
            modelContext: context,
            listBackups: { try await backupService.listBackups() },
            downloadBackup: { try await backupService.downloadBackup(metadata: $0) },
            flag: .standard
        )
        guard !AutoRestoreFlag.standard.isSet,
              (try? LocalDataRestorer(modelContext: context).isStoreEmpty()) == true else { return }

        autoRestore.start(isSignedIn: { authService.isAuthenticated }) { try await restore.run() }
    }
}

/// The app-wide cloud status banner. A failed auto-restore gets Try Again
/// and a close button.
private struct CloudStatusBanner: View {
    let message: String
    var autoRestore: AutoRestoreViewModel?

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.leading)

            if let autoRestore, autoRestore.isFailed {
                if autoRestore.canRetry {
                    Button("Try Again") {
                        _ = autoRestore.retry()
                    }
                    .font(.caption.weight(.semibold))
                }

                Button {
                    autoRestore.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
