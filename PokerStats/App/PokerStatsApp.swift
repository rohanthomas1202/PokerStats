import SwiftUI
import SwiftData

@main
struct PokerStatsApp: App {
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var autoRestore = AutoRestoreViewModel()
    @State private var localDataOwnership = LocalDataOwnershipViewModel()

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
                .environment(localDataOwnership)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--seed-screenshot-data") {
                        let context = container.mainContext
                        let count = (try? context.fetchCount(FetchDescriptor<Session>())) ?? 0
                        if count == 0 {
                            DataSeeder.seed(into: context)
                        }
                    }
                }
                // An inset, not an overlay, so the banner pushes content down
                // instead of covering the navigation bar (#258).
                .safeAreaInset(edge: .top, spacing: 0) {
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
                .modifier(LocalDataOwnershipPrompt(
                    ownership: localDataOwnership,
                    authService: authService,
                    modelContext: container.mainContext
                ))
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
        let backupService = BackupService(authService: authService, modelContext: context, client: authService.client)
        let restore = AutoRestore(
            modelContext: context,
            listBackups: { try await backupService.listBackups() },
            downloadBackup: { try await backupService.downloadBackup(metadata: $0) },
            flag: .standard,
            checkCanWrite: { try authService.checkRestoreCanWrite() },
            owner: authService.localDataOwner
        )
        guard !restore.flag.isSet,
              (try? LocalDataRestorer(modelContext: context).isStoreEmpty()) == true else { return }

        // Account deletion stops it and waits for it (#61).
        autoRestore.start(isSignedIn: { authService.isAuthenticated }) {
            try await authService.performCloudWork { try await restore.run() }
        }
    }
}

/// The app-wide cloud status banner. A failed auto-restore gets a close button,
/// and Try Again when retrying can help. Both are at least 44 pt.
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
                    Button {
                        _ = autoRestore.retry()
                    } label: {
                        Text("Try Again")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }

                Button {
                    autoRestore.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
