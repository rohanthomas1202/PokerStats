import SwiftUI
import SwiftData

/// Context-sensitive session tab: shows StartSessionView or ActiveSessionView.
struct SessionTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startTime, order: .reverse)
    private var allSessions: [Session]

    @State private var navigationPath = NavigationPath()

    private var activeSession: Session? {
        allSessions.first { $0.status == .active }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let activeSession {
                    ActiveSessionView(
                        viewModel: ActiveSessionViewModel(
                            session: activeSession,
                            modelContext: modelContext
                        )
                    )
                } else {
                    StartSessionView()
                }
            }
        }
    }
}
