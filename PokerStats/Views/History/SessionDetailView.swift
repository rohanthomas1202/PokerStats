import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: Session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SessionDetailViewModel?

    private var vm: SessionDetailViewModel {
        viewModel ?? SessionDetailViewModel(session: session, modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Financial card
                financialCard

                // Stats card
                statsCard

                // Hand log
                handLogSection

                // Notes
                if !session.notes.isEmpty {
                    notesSection
                }

                // Delete button
                Button(role: .destructive) {
                    vm.showDeleteConfirmation = true
                } label: {
                    Label("Delete Session", systemImage: "trash")
                        .font(.subheadline)
                }
                .padding(.top, 16)
            }
            .padding()
        }
        .navigationTitle("\(session.stakes) \(session.gameType.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    vm.beginEditing()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { vm.isEditing },
            set: { _ in vm.cancelEditing() }
        )) {
            editSheet
        }
        .confirmationDialog("Delete Session?", isPresented: Binding(
            get: { vm.showDeleteConfirmation },
            set: { vm.showDeleteConfirmation = $0 }
        )) {
            Button("Delete", role: .destructive) {
                vm.deleteSession()
                dismiss()
            }
        } message: {
            Text("This will permanently delete this session and all its hand data.")
        }
        .onAppear {
            viewModel = SessionDetailViewModel(session: session, modelContext: modelContext)
        }
    }

    // MARK: - Financial Card

    private var financialCard: some View {
        VStack(spacing: 12) {
            // Headline P/L
            Text(CurrencyFormatter.formatSigned(session.netProfit))
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(session.netProfit >= 0 ? .green : .red)

            Text("\(DateFormatting.formatFull(session.startTime)) - \(DurationFormatter.format(session.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !session.location.isEmpty {
                Text(session.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 0) {
                StatCardView(title: "Buy-In", value: CurrencyFormatter.format(session.buyIn))
                if session.rebuys > 0 {
                    StatCardView(title: "Rebuys", value: CurrencyFormatter.format(session.rebuys))
                }
                StatCardView(title: "Cash Out", value: CurrencyFormatter.format(session.cashOut))
                if let hourly = session.hourlyRate {
                    StatCardView(title: "$/hr", value: ComputedStats.formatHourlyRate(hourly))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        let stats = vm.stats
        return VStack(spacing: 12) {
            Text("Session Stats")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if stats.totalHands > 0 {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCardView(title: "Hands", value: "\(stats.totalHands)")
                    StatCardView(title: "VPIP", value: ComputedStats.formatPercent(stats.vpip))
                    StatCardView(title: "PFR", value: ComputedStats.formatPercent(stats.pfr))
                    StatCardView(title: "Fold to 3B", value: ComputedStats.formatPercent(stats.foldTo3BetPercent))
                    StatCardView(title: "C-Bet", value: ComputedStats.formatPercent(stats.cBetPercent))
                    StatCardView(title: "WTSD", value: ComputedStats.formatPercent(stats.wtsdPercent))
                    StatCardView(title: "W$SD", value: ComputedStats.formatPercent(stats.wsdPercent))
                    StatCardView(
                        title: "Folded",
                        value: ComputedStats.formatPercent(
                            stats.totalHands > 0
                            ? Double(stats.handsFolded) / Double(stats.totalHands)
                            : nil
                        )
                    )
                }
            } else {
                Text("No hands logged for this session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Hand Log

    private var handLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hand Log (\(session.handCount))")
                .font(.headline)

            if vm.sortedHands.isEmpty {
                Text("No hands were logged for this session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.sortedHands) { hand in
                    HStack {
                        Text("#\(hand.handNumber)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)

                        Text(hand.preflopAction.shortName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 24, height: 24)
                            .background(preflopColor(hand.preflopAction).opacity(0.3))
                            .clipShape(Circle())

                        Text(hand.actionSummary)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        if let result = hand.postflopResult {
                            Image(systemName: result.isWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isWin ? .green : .red)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)

                    if hand.id != vm.sortedHands.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func preflopColor(_ action: PreflopAction) -> Color {
        switch action {
        case .fold: .gray
        case .call: .blue
        case .raise: .orange
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            Text(session.notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Financial") {
                    HStack {
                        Text("Buy-In $")
                        TextField("Amount", text: Binding(
                            get: { vm.editBuyIn },
                            set: { vm.editBuyIn = $0 }
                        ))
                        .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Rebuys $")
                        TextField("Amount", text: Binding(
                            get: { vm.editRebuys },
                            set: { vm.editRebuys = $0 }
                        ))
                        .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Cash Out $")
                        TextField("Amount", text: Binding(
                            get: { vm.editCashOut },
                            set: { vm.editCashOut = $0 }
                        ))
                        .keyboardType(.numberPad)
                    }
                }

                Section("Details") {
                    TextField("Location", text: Binding(
                        get: { vm.editLocation },
                        set: { vm.editLocation = $0 }
                    ))
                    TextField("Stakes", text: Binding(
                        get: { vm.editStakes },
                        set: { vm.editStakes = $0 }
                    ))
                }

                Section("Notes") {
                    TextField("Session notes", text: Binding(
                        get: { vm.editNotes },
                        set: { vm.editNotes = $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.cancelEditing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { vm.saveEdits() }
                }
            }
        }
    }
}
