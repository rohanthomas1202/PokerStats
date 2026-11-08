import SwiftUI
import SwiftData

struct ExportShareRow: View {
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
                            Label("Couldn't remove the temporary files. Please try again.", systemImage: "exclamationmark.triangle")
                            Button("Try Again") {
                                Task {
                                    await viewModel.cleanup()
                                    await viewModel.prepare(container: modelContext.container)
                                }
                            }
                        case .failed:
                            Label("Couldn't export your data. Please try again.", systemImage: "exclamationmark.triangle")
                            Button("Try Again") {
                                Task { await viewModel.prepare(container: modelContext.container) }
                            }
                        }
                    } footer: {
                        Text("Exports three files with your poker data. The JSON file is the lossless copy. Tap Done after sharing to remove temporary files.")
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
