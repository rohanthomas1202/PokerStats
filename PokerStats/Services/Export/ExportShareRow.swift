import SwiftUI
import SwiftData

struct ExportShareRow: View {
    static let footer = "Creates three files with all your sessions and hands. Anyone you share them with can see your results. The JSON file keeps every detail. The CSV files open in spreadsheet apps."

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ExportShareViewModel()
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Export your data", systemImage: "square.and.arrow.up")
        }
        .disabled(viewModel.state == .removing)
        // ShareLink has no completion callback. Keep files readable until the export
        // sheet closes, rather than deleting them while a destination is still reading.
        .sheet(isPresented: $isPresented, onDismiss: {
            Task { await viewModel.cleanup() }
        }) {
            NavigationStack {
                Form {
                    Section {
                        switch viewModel.state {
                        case .idle, .generating:
                            ProgressView("Preparing your export…")
                        case .ready(let files):
                            // Only file URLs; no subject, message, or account/session metadata.
                            ShareLink(items: files.urls) { url in
                                SharePreview(url.lastPathComponent)
                            } label: {
                                Label("Share export files", systemImage: "square.and.arrow.up")
                            }
                        case .removing:
                            ProgressView("Removing temporary files…")
                        case .cleanupFailed:
                            Label(ExportShareViewModel.cleanupFailedMessage, systemImage: "exclamationmark.triangle")
                            Button("Try Again") {
                                Task {
                                    await viewModel.cleanup()
                                    await viewModel.prepare(container: modelContext.container)
                                }
                            }
                        case .failed:
                            Label(ExportShareViewModel.failedMessage, systemImage: "exclamationmark.triangle")
                            Button("Try Again") {
                                Task { await viewModel.prepare(container: modelContext.container) }
                            }
                        }
                    } footer: {
                        Text(Self.footer)
                    }
                }
                .navigationTitle("Export your data")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
                .task { await viewModel.prepare(container: modelContext.container) }
            }
        }
    }
}
