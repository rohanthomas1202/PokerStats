import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @State private var viewModel = SettingsViewModel()
    @State private var authViewModel: AuthViewModel?
    @State private var isShowingDeleteAccount = false
    @State private var isShowingDeleteAccountFinal = false
    @State private var isSeeding = false
    @State private var seedComplete = false

    var body: some View {
        Form {
            // MARK: - Account Section
            Section("Account") {
                if authService.isAuthenticated {
                    HStack {
                        Label(authService.displayEmail, systemImage: "person.circle.fill")
                        Spacer()
                    }

                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("Cloud Backup", systemImage: "icloud")
                    }

                    Button {
                        authViewModel?.requestSignOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    if let feedback = authViewModel?.signOutFeedback {
                        Label(feedback, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if authViewModel == nil {
                            authViewModel = AuthViewModel(authService: authService)
                        }
                        authViewModel?.isShowingSignIn = true
                    } label: {
                        Label("Sign In", systemImage: "person.circle")
                    }

                    HStack {
                        Label("Cloud Backup", systemImage: "icloud")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Sign in to enable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Defaults Section
            Section("Defaults") {
                HStack {
                    Text("Default Buy-In")
                    Spacer()
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Amount", text: $viewModel.defaultBuyIn)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Picker("Default Stakes", selection: $viewModel.defaultStakes) {
                    ForEach(CommonStakes.allCases) { stakes in
                        Text(stakes.rawValue).tag(stakes.rawValue)
                    }
                }

                Picker("Default Game", selection: $viewModel.defaultGameType) {
                    ForEach(GameType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            // MARK: - Data Section
            Section("Data") {
                #if DEBUG
                Button {
                    isSeeding = true
                    DataSeeder.seed(into: modelContext)
                    isSeeding = false
                    seedComplete = true
                } label: {
                    Label(isSeeding ? "Seeding..." : "Seed 6 Months Test Data", systemImage: "wand.and.stars")
                }
                .disabled(isSeeding)
                #endif

                Button(role: .destructive) {
                    viewModel.showDeleteAllConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }

                if authService.isAuthenticated {
                    Button(role: .destructive) {
                        isShowingDeleteAccount = true
                    } label: {
                        Label("Delete Account", systemImage: "person.slash")
                    }
                }
            }

            // MARK: - About Section
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: AppLinks.privacyPolicy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: URL(string: "https://github.com")!) {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.pokerBackground)
        .navigationTitle("Settings")
        .overlay {
            if authViewModel?.isDeletingAccount == true {
                // Blocks the form while the deletion request runs.
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Deleting Account…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .navigationBarBackButtonHidden(authViewModel?.isDeletingAccount == true)
        .onAppear {
            viewModel.loadSettings(from: modelContext)
            if authViewModel == nil {
                authViewModel = AuthViewModel(authService: authService)
            }
        }
        .onChange(of: viewModel.defaultBuyIn) { _, _ in
            viewModel.saveSettings(to: modelContext)
        }
        .onChange(of: viewModel.defaultStakes) { _, _ in
            viewModel.saveSettings(to: modelContext)
        }
        .onChange(of: viewModel.defaultGameType) { _, _ in
            viewModel.saveSettings(to: modelContext)
        }
        .modifier(SignInSheet(authViewModel: authViewModel))
        .modifier(SignOutConfirmation(authViewModel: authViewModel))
        .modifier(DeleteAllDataFailureAlert(viewModel: viewModel))
        .alert(SettingsViewModel.localWipeFailedTitle, isPresented: $viewModel.localWipeFailed) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Local Data", role: .destructive) {
                viewModel.wipeAfterAccountDeletion(from: modelContext)
            }
        } message: {
            Text(SettingsViewModel.localWipeFailedMessage)
        }
        .alert("Delete All Data?", isPresented: $viewModel.showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                viewModel.showDeleteAllSecondConfirmation = true
            }
        } message: {
            Text("This will permanently delete all sessions and hand data. This cannot be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $viewModel.showDeleteAllSecondConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Delete All", role: .destructive) {
                viewModel.deleteAllData(from: modelContext)
            }
        } message: {
            Text("All poker data will be permanently lost.")
        }
        .alert("Delete Account?", isPresented: $isShowingDeleteAccount) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Account", role: .destructive) {
                isShowingDeleteAccountFinal = true
            }
        } message: {
            Text("This will permanently delete your account and all cloud data. Local data will also be removed.")
        }
        .alert("Test Data Seeded", isPresented: $seedComplete) {
            Button("OK") { }
        } message: {
            Text("6 months of realistic session data has been added.")
        }
        .alert(
            authViewModel?.deleteAccountFailure?.title ?? "",
            isPresented: Binding(
                get: { authViewModel?.deleteAccountFailure != nil },
                set: { if !$0 { authViewModel?.deleteAccountFailure = nil } }
            ),
            presenting: authViewModel?.deleteAccountFailure
        ) { failure in
            if failure.kind == .appleDisconnected && !authService.isAuthenticated {
                // Signed out by the Apple revocation: sign in first, then delete again.
                Button("Sign In") {
                    authViewModel?.isShowingSignIn = true
                }
                Button("Cancel", role: .cancel) { }
            } else if failure.kind == .notRetryable {
                Button("OK", role: .cancel) { }
            } else {
                Button("Try Again") {
                    authViewModel?.retryDeleteAccount()
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: { failure in
            Text(failure.message)
        }
        .alert("This cannot be undone.", isPresented: $isShowingDeleteAccountFinal) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Delete My Account", role: .destructive) {
                authViewModel?.deleteAccount {
                    viewModel.wipeAfterAccountDeletion(from: modelContext)
                }
            }
        } message: {
            Text("Your account, all cloud backups, and all local data will be permanently deleted.")
        }
    }
}

/// The sign-in sheet. While it's up, the "Stats From Another Account" choice
/// waits, so it can show once the sheet has closed (#69).
private struct SignInSheet: ViewModifier {
    let authViewModel: AuthViewModel?
    @Environment(LocalDataOwnershipViewModel.self) private var ownership

    private var isPresented: Binding<Bool> {
        Binding(
            get: { authViewModel?.isShowingSignIn ?? false },
            set: { authViewModel?.isShowingSignIn = $0 }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented, onDismiss: { ownership.resumePrompt() }) {
                if let authViewModel {
                    SignInView(authViewModel: authViewModel)
                        .onAppear { ownership.deferPrompt() }
                }
            }
    }
}

/// Delete All Data failed: say so instead of failing silently (#263).
private struct DeleteAllDataFailureAlert: ViewModifier {
    let viewModel: SettingsViewModel

    private var isPresented: Binding<Bool> {
        Binding(
            get: { viewModel.deleteAllDataFailure != nil },
            set: { if !$0 { viewModel.deleteAllDataFailure = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(
                SettingsViewModel.deleteAllDataFailedTitle,
                isPresented: isPresented,
                presenting: viewModel.deleteAllDataFailure
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
    }
}

/// Sign Out asks first, then announces the feedback for VoiceOver.
private struct SignOutConfirmation: ViewModifier {
    let authViewModel: AuthViewModel?

    private var isPresented: Binding<Bool> {
        Binding(
            get: { authViewModel?.isShowingSignOutConfirmation ?? false },
            set: { authViewModel?.isShowingSignOutConfirmation = $0 }
        )
    }

    private var feedback: String? {
        authViewModel?.signOutFeedback
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Sign out?", isPresented: isPresented, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    _ = authViewModel?.confirmSignOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your stats stay on this iPhone.")
            }
            .onChange(of: feedback) { _, feedback in
                guard let feedback else { return }
                AccessibilityNotification.Announcement(feedback).post()
            }
    }
}
