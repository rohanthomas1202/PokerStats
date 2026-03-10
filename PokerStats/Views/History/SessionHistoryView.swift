import SwiftUI
import SwiftData

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startTime, order: .reverse)
    private var allSessions: [Session]

    @State private var viewModel = SessionListViewModel()
    @State private var navigationPath = NavigationPath()

    private var completedSessions: [Session] {
        allSessions.filter { $0.status == .completed }
    }

    private var filteredSessions: [Session] {
        viewModel.filteredSessions(completedSessions)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if completedSessions.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No Sessions Yet",
                        message: "Completed sessions will appear here."
                    )
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .searchable(text: $viewModel.searchText, prompt: "Search by location or stakes")
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(session: session)
            }
        }
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            // Aggregate summary bar
            let agg = viewModel.aggregateStats(filteredSessions)
            HStack {
                Text("\(agg.sessions) sessions")
                Spacer()
                Text(CurrencyFormatter.formatSigned(agg.profit))
                    .foregroundStyle(agg.profit >= 0 ? Color.pokerProfit : Color.pokerLoss)
                Spacer()
                Text("\(Int(agg.hours))h played")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                let grouped = viewModel.groupedByMonth(filteredSessions)
                ForEach(grouped, id: \.0) { monthLabel, monthSessions in
                    Section(monthLabel) {
                        ForEach(monthSessions) { session in
                            Button {
                                navigationPath.append(session)
                            } label: {
                                SessionRowView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}
