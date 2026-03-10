import SwiftUI

struct ActiveSessionView: View {
    @Bindable var viewModel: ActiveSessionViewModel
    @State private var handLogger = HandLoggerViewModel()
    @State private var cashOutText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Timer and status
            sessionStatusBar
                .padding()

            // Quick stats pills
            quickStatsPills
                .padding(.horizontal)

            Divider()
                .padding(.vertical, 8)

            // Recent hands feed
            recentHandsFeed
                .frame(maxHeight: .infinity)

            Divider()

            // Action buttons
            actionButtons
                .padding()

            // LOG HAND button (dominant element)
            logHandButton
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .navigationTitle("Live Session")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.isShowingHandLogger) {
            HandLoggerSheet(viewModel: handLogger) { hand in
                viewModel.addHand(hand)
                handLogger.reset()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isShowingRebuy) {
            rebuySheet
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $viewModel.isShowingEndSession) {
            endSessionSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.isShowingMentalCheck) {
            MentalCheckSheet(
                tiltLevel: $viewModel.tiltLevel,
                energyLevel: $viewModel.energyLevel,
                focusLevel: $viewModel.focusLevel
            ) {
                viewModel.saveMentalLevels()
            }
            .presentationDetents([.medium])
        }
        .alert("Session Still Active?", isPresented: $viewModel.isShowingStaleAlert) {
            Button("Continue Session") { }
            Button("End Session", role: .destructive) {
                viewModel.isShowingEndSession = true
            }
        } message: {
            Text("This session has been running for over 12 hours. Would you like to continue or end it?")
        }
    }

    // MARK: - Session Status Bar

    private var sessionStatusBar: some View {
        VStack(spacing: 12) {
            // Timer
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(DurationFormatter.formatTimer(viewModel.elapsed))
                    .font(.system(size: 40, weight: .light, design: .monospaced))
            }

            // Running P/L and hand count
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("Invested")
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)
                    Text(CurrencyFormatter.format(viewModel.session.totalInvested))
                        .font(.headline)
                        .foregroundStyle(Color.pokerLoss)
                }

                VStack(spacing: 2) {
                    Text("Hands")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.handCount)")
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - Quick Stats Grid (2x2)

    private var quickStatsPills: some View {
        VStack(spacing: 8) {
            HStack {
                PlayStyleLabelView(
                    style: PlayStyle.classify(
                        vpip: viewModel.sessionStats.vpip,
                        pfr: viewModel.sessionStats.pfr
                    )
                )
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                miniStatCard("VPIP", ComputedStats.formatPercent(viewModel.sessionStats.vpip))
                miniStatCard("PFR", ComputedStats.formatPercent(viewModel.sessionStats.pfr))
                miniStatCard("C-Bet", ComputedStats.formatPercent(viewModel.sessionStats.cBetPercent))
                miniStatCard("WTSD", ComputedStats.formatPercent(viewModel.sessionStats.wtsdPercent))
            }
        }
    }

    private func miniStatCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pokerTextPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.pokerTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .pokerCard()
    }

    // MARK: - Recent Hands Feed

    private var recentHandsFeed: some View {
        Group {
            if viewModel.recentHands.isEmpty {
                VStack {
                    Spacer()
                    Text("Tap 'Log Hand' each time you're dealt in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.recentHands) { hand in
                        HStack {
                            Text("#\(hand.handNumber)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)

                            preflopBadge(hand.preflopAction)

                            Text(hand.actionSummary)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            if let result = hand.postflopResult {
                                Image(systemName: result.isWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.isWin ? .green : .red)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let hand = viewModel.recentHands[index]
                            viewModel.deleteHand(hand)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func preflopBadge(_ action: PreflopAction) -> some View {
        Text(action.shortName)
            .font(.caption)
            .fontWeight(.bold)
            .frame(width: 24, height: 24)
            .background(
                action == .fold ? Color.gray.opacity(0.3) :
                action == .call ? Color.blue.opacity(0.3) :
                Color.orange.opacity(0.3)
            )
            .clipShape(Circle())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.isShowingRebuy = true
            } label: {
                Label("Rebuy", systemImage: "dollarsign.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.isShowingMentalCheck = true
            } label: {
                Label("Check In", systemImage: "brain.head.profile")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.purple)

            Button {
                viewModel.isShowingNoteEditor.toggle()
            } label: {
                Label("Note", systemImage: "note.text")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.isShowingEndSession = true
            } label: {
                Label("End", systemImage: "stop.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Log Hand Button

    private var logHandButton: some View {
        Button {
            handLogger.reset()
            viewModel.isShowingHandLogger = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "hand.raised.fill")
                    .font(.title)
                Text("Log Hand")
                    .font(.headline)
                Text("#\(viewModel.session.nextHandNumber)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.pokerAccent, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Rebuy Sheet

    private var rebuySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                CurrencyField(title: "Rebuy Amount", text: $viewModel.rebuyAmountText)
                    .padding(.top)

                Button {
                    viewModel.addRebuy()
                    viewModel.isShowingRebuy = false
                } label: {
                    Text("Add Rebuy")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pokerAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(Double(viewModel.rebuyAmountText) == nil)

                Spacer()
            }
            .padding()
            .navigationTitle("Rebuy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isShowingRebuy = false }
                }
            }
        }
    }

    // MARK: - End Session Sheet

    private var endSessionSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Invested: \(CurrencyFormatter.format(viewModel.session.totalInvested))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                CurrencyField(title: "Cash Out Amount", text: $cashOutText)

                if let cashOut = Double(cashOutText) {
                    let profit = cashOut - viewModel.session.totalInvested
                    HStack {
                        Text("Net P/L:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.formatSigned(profit))
                            .fontWeight(.bold)
                            .foregroundStyle(profit >= 0 ? Color.pokerProfit : Color.pokerLoss)
                    }
                    .font(.headline)
                }

                Button {
                    if let cashOut = Double(cashOutText) {
                        viewModel.endSession(cashOut: cashOut)
                        viewModel.isShowingEndSession = false
                    }
                } label: {
                    Text("End Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(Double(cashOutText) == nil)

                Spacer()
            }
            .padding()
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.isShowingEndSession = false }
                }
            }
        }
    }
}
