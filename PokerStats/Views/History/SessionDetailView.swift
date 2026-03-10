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

                // Mental state card
                if session.tiltLevel != nil || session.energyLevel != nil || session.focusLevel != nil {
                    mentalStateCard
                }

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
                .foregroundStyle(session.netProfit >= 0 ? Color.pokerProfit : Color.pokerLoss)

            Text("\(DateFormatting.formatFull(session.startTime)) - \(DurationFormatter.format(session.duration))")
                .font(.caption)
                .foregroundStyle(Color.pokerTextSecondary)

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
        .pokerCard()
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        let stats = vm.stats
        return VStack(spacing: 12) {
            HStack {
                Text("Session Stats")
                    .font(.headline)
                PlayStyleLabelView(
                    style: PlayStyle.classify(vpip: stats.vpip, pfr: stats.pfr)
                )
                Spacer()
            }

            if stats.totalHands > 0 {
                // Play style chart (small)
                PlayStyleChartView(vpip: stats.vpip, pfr: stats.pfr)
                    .scaleEffect(0.6)
                    .frame(height: 150)

                // 2-column stat grid with range bars and help icons
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCardView(
                        title: "VPIP",
                        value: ComputedStats.formatPercent(stats.vpip),
                        statDef: .vpip,
                        rangeValue: stats.vpip,
                        rangeGoodRange: StatDefinition.vpip.goodRange
                    )
                    StatCardView(
                        title: "PFR",
                        value: ComputedStats.formatPercent(stats.pfr),
                        statDef: .pfr,
                        rangeValue: stats.pfr,
                        rangeGoodRange: StatDefinition.pfr.goodRange
                    )
                    StatCardView(
                        title: "C-Bet",
                        value: ComputedStats.formatPercent(stats.cBetPercent),
                        statDef: .cBet,
                        rangeValue: stats.cBetPercent,
                        rangeGoodRange: StatDefinition.cBet.goodRange
                    )
                    StatCardView(
                        title: "WTSD",
                        value: ComputedStats.formatPercent(stats.wtsdPercent),
                        statDef: .wtsd,
                        rangeValue: stats.wtsdPercent,
                        rangeGoodRange: StatDefinition.wtsd.goodRange
                    )
                }

                // Secondary stats
                HStack(spacing: 8) {
                    StatCardView(title: "Hands", value: "\(stats.totalHands)")
                    StatCardView(
                        title: "Fold to 3B",
                        value: ComputedStats.formatPercent(stats.foldTo3BetPercent),
                        statDef: .foldTo3Bet
                    )
                    StatCardView(
                        title: "W$SD",
                        value: ComputedStats.formatPercent(stats.wsdPercent),
                        statDef: .wsd
                    )
                }

                // ROI display
                if session.status == .completed && session.totalInvested > 0 {
                    let roi = (session.netProfit / session.totalInvested) * 100
                    HStack {
                        Text("Session ROI")
                            .font(.caption)
                            .foregroundStyle(Color.pokerTextSecondary)
                        Spacer()
                        Text(String(format: "%+.1f%%", roi))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(roi >= 0 ? Color.pokerProfit : Color.pokerLoss)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("No hands logged for this session")
                    .font(.subheadline)
                    .foregroundStyle(Color.pokerTextSecondary)
                    .padding()
            }
        }
        .padding()
        .pokerCard()
    }

    // MARK: - Mental State Card

    private var mentalStateCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Mental State")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                if let tilt = session.tiltLevel {
                    mentalMetricBadge(type: .tilt, level: tilt)
                }
                if let energy = session.energyLevel {
                    mentalMetricBadge(type: .energy, level: energy)
                }
                if let focus = session.focusLevel {
                    mentalMetricBadge(type: .focus, level: focus)
                }
            }
        }
        .padding()
        .pokerCard()
    }

    private func mentalMetricBadge(type: MentalMetricType, level: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundStyle(mentalColor(type: type, level: level))
            Text("\(level)/5")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(type.displayName)
                .font(.caption2)
                .foregroundStyle(Color.pokerTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .pokerCard()
    }

    private func mentalColor(type: MentalMetricType, level: Int) -> Color {
        if type.higherIsBetter {
            switch level {
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            case 4: return .mint
            case 5: return .green
            default: return .gray
            }
        } else {
            switch level {
            case 1: return .green
            case 2: return .mint
            case 3: return .yellow
            case 4: return .orange
            case 5: return .red
            default: return .gray
            }
        }
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
                                .foregroundStyle(result.isWin ? Color.pokerProfit : Color.pokerLoss)
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
        .pokerCard()
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
        .pokerCard()
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
