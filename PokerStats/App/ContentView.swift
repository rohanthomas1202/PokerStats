import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var activeSessions: [Session] = []

    private var hasActiveSession: Bool {
        !activeSessions.isEmpty
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.fill", value: 0) {
                DashboardView(selectedTab: $selectedTab)
            }

            Tab("Session", systemImage: hasActiveSession ? "play.fill" : "plus.circle.fill", value: 1) {
                SessionTabView()
            }
            .badge(hasActiveSession ? Text("Live") : nil)

            Tab("History", systemImage: "clock.fill", value: 2) {
                SessionHistoryView()
            }
        }
        .background(Color.pokerBackground)
        .onAppear(perform: loadActiveSessions)
        .onChange(of: selectedTab) { _, _ in loadActiveSessions() }
    }

    private func loadActiveSessions() {
        let active = SessionStatus.active.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.statusRaw == active }
        )
        activeSessions = (try? modelContext.fetch(descriptor)) ?? []
    }
}
