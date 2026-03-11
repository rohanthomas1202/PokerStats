import SwiftUI
import SwiftData

struct LeakFinderView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LeakFinderViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Profile picker
                profilePicker

                if viewModel.hasEnoughData {
                    // Overall health
                    overallHealthCard

                    // Insights list
                    ForEach(viewModel.insights) { insight in
                        InsightCardView(insight: insight)
                    }
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color.pokerBackground)
        .navigationTitle("Leak Finder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadData(from: modelContext)
        }
        .onChange(of: viewModel.selectedProfile) {
            viewModel.loadData(from: modelContext)
        }
    }

    // MARK: - Profile Picker

    private var profilePicker: some View {
        Picker("Game Format", selection: $viewModel.selectedProfile) {
            ForEach(ReferenceProfile.allCases) { profile in
                Text(profile.displayName).tag(profile)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Overall Health

    private var overallHealthCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Overall Assessment")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                // Overall rating indicator
                VStack(spacing: 6) {
                    Circle()
                        .fill(overallColor)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: overallIcon)
                                .font(.title3)
                                .foregroundStyle(.white)
                        }

                    Text(viewModel.overallRating.rawValue)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(overallColor)
                }

                // Breakdown counts
                VStack(alignment: .leading, spacing: 6) {
                    ratingCountRow(label: "Healthy", count: viewModel.insights.filter { $0.rating == .healthy }.count, color: .pokerProfit)
                    ratingCountRow(label: "Borderline", count: viewModel.borderlineCount, color: .yellow)
                    ratingCountRow(label: "Leaks", count: viewModel.leakCount, color: .pokerLoss)
                }

                Spacer()
            }

            Text("Based on \(viewModel.totalHands) hands analyzed against \(viewModel.selectedProfile.displayName) ranges.")
                .font(.caption)
                .foregroundStyle(Color.pokerTextSecondary)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    private func ratingCountRow(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.pokerTextSecondary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
        }
        .frame(width: 140)
    }

    private var overallColor: Color {
        switch viewModel.overallRating {
        case .solid: .pokerProfit
        case .needsWork: .yellow
        case .leaking: .pokerLoss
        }
    }

    private var overallIcon: String {
        switch viewModel.overallRating {
        case .solid: "checkmark"
        case .needsWork: "exclamationmark.triangle"
        case .leaking: "xmark"
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.pokerTextTertiary)

            Text("Not Enough Data")
                .font(.headline)

            Text("Log at least \(LeakFinder.minimumHands) hands to get leak analysis. You have \(viewModel.totalHands) so far.")
                .font(.subheadline)
                .foregroundStyle(Color.pokerTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .pokerCard(cornerRadius: 16)
    }
}
