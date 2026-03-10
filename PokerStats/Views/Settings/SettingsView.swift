import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
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

            Section("Data") {
                Button(role: .destructive) {
                    viewModel.showDeleteAllConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com")!) {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            viewModel.loadSettings(from: modelContext)
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
    }
}
