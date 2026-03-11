import SwiftUI

struct BackupSettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = BackupViewModel()

    var body: some View {
        List {
            // Status section
            Section {
                if let lastDate = viewModel.lastBackupDate {
                    HStack {
                        Text("Last Backup")
                        Spacer()
                        Text(lastDate)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No backups yet")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.createBackup() }
                } label: {
                    HStack {
                        Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        if viewModel.isBackingUp {
                            ProgressView()
                        }
                    }
                }
                .disabled(!viewModel.canBackup)
            } header: {
                Text("Backup")
            } footer: {
                Text("Backups are encrypted and stored securely in the cloud. Only you can access your data.")
            }

            // Success/error messages
            if let success = viewModel.successMessage {
                Section {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            // Backup history
            if !viewModel.backups.isEmpty {
                Section("Backup History") {
                    ForEach(viewModel.backups) { backup in
                        Button {
                            viewModel.initiateRestore(backup: backup)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(backup.formattedDate)
                                    .foregroundStyle(.primary)
                                Text("\(backup.sessionCount) sessions, \(backup.handCount) hands \u{2022} \(backup.formattedSize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if viewModel.isLoadingBackups {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.pokerBackground)
        .navigationTitle("Cloud Backup")
        .onAppear {
            viewModel.configure(authService: authService, modelContext: modelContext)
            Task { await viewModel.loadBackups() }
        }
        .alert("Restore Backup?", isPresented: $viewModel.isShowingRestoreConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Back Up First, Then Restore") {
                Task { await viewModel.backupThenRestore() }
            }
            Button("Restore Now", role: .destructive) {
                Task { await viewModel.confirmRestore() }
            }
        } message: {
            if let backup = viewModel.selectedBackup {
                Text("This will replace all local data with the backup from \(backup.formattedDate). This cannot be undone.\n\n\(backup.sessionCount) sessions, \(backup.handCount) hands will be restored.")
            }
        }
        .overlay {
            if viewModel.isRestoring {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Restoring backup...")
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}
