import SwiftUI

/// Sub-3-second hand logging sheet using progressive disclosure.
/// Fold = 1 tap. Max = 5 taps.
struct HandLoggerSheet: View {
    @Bindable var viewModel: HandLoggerViewModel
    let onComplete: (Hand) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress indicator
                progressDots
                    .padding(.top, 8)

                Spacer()

                // Current step content
                Group {
                    switch viewModel.currentStep {
                    case .position:
                        positionStep
                    case .preflop:
                        preflopStep
                    case .threeBetQualifier:
                        threeBetQualifierStep
                    case .threeBetResponse:
                        threeBetResponseStep
                    case .postflopResult:
                        postflopResultStep
                    case .cBet:
                        cBetStep
                    case .done:
                        EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Optional note
                if viewModel.showNoteField {
                    TextField("Add a note...", text: $viewModel.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Log Hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if viewModel.canGoBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.goBack()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showNoteField.toggle()
                    } label: {
                        Image(systemName: viewModel.showNoteField ? "note.text.badge.plus" : "note.text")
                    }
                }
            }
            .onChange(of: viewModel.isDone) { _, isDone in
                if isDone {
                    let hand = viewModel.buildHand()
                    onComplete(hand)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStepIndex ? Color.pokerAccent : Color.pokerTextTertiary)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var totalSteps: Int {
        // Varies by path, approximate with max
        6
    }

    private var currentStepIndex: Int {
        switch viewModel.currentStep {
        case .position: 0
        case .preflop: 1
        case .threeBetQualifier: 2
        case .threeBetResponse: 3
        case .postflopResult: viewModel.preflopAction == .call ? 2 : 3
        case .cBet: 4
        case .done: 5
        }
    }

    // MARK: - Step 0: Position

    private var positionStep: some View {
        VStack(spacing: 16) {
            Text("Your Position")
                .font(.title2)
                .fontWeight(.bold)

            Text("Where are you seated?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SeatPosition.allPlayable, id: \.self) { position in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectPosition(position)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(position.displayName)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(position.longName)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.pokerAccent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectPosition(.unknown)
                }
            } label: {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundStyle(Color.pokerTextSecondary)
            }
        }
    }

    // MARK: - Step 1: Preflop Action

    private var preflopStep: some View {
        VStack(spacing: 16) {
            Text("Preflop Action")
                .font(.title2)
                .fontWeight(.bold)

            Text("What did you do preflop?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                actionButton("Fold", color: .gray) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectPreflopAction(.fold)
                    }
                }

                actionButton("Call", color: .blue) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectPreflopAction(.call)
                    }
                }

                actionButton("Raise", color: .orange) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectPreflopAction(.raise)
                    }
                }
            }
        }
    }

    // MARK: - Step 1b: 3-Bet Qualifier

    private var threeBetQualifierStep: some View {
        VStack(spacing: 16) {
            Text("Faced a Re-Raise?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Did someone 3-bet after your raise?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                actionButton("No", color: .green) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectFaced3Bet(false)
                    }
                }

                actionButton("Yes", color: .red) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectFaced3Bet(true)
                    }
                }
            }
        }
    }

    // MARK: - Step 1c: 3-Bet Response

    private var threeBetResponseStep: some View {
        VStack(spacing: 16) {
            Text("Your Response?")
                .font(.title2)
                .fontWeight(.bold)

            Text("What did you do facing the 3-bet?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                actionButton("Folded", color: .gray) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectThreeBetResponse(.folded)
                    }
                }

                actionButton("Called", color: .blue) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectThreeBetResponse(.called)
                    }
                }

                actionButton("4-Bet+", color: .orange) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectThreeBetResponse(.fourBetPlus)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Postflop Result

    private var postflopResultStep: some View {
        VStack(spacing: 16) {
            Text("Hand Result")
                .font(.title2)
                .fontWeight(.bold)

            Text("How did the hand end?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                resultButton("Won Preflop", subtitle: "No flop dealt", color: .green, result: .wonPreflop)
                resultButton("Won Before Showdown", subtitle: "Opponent(s) folded", color: .green, result: .wonBeforeShowdown)
                resultButton("Lost Before Showdown", subtitle: "You folded post-flop", color: .red, result: .lostBeforeShowdown)
                resultButton("Won at Showdown", subtitle: "Best hand at showdown", color: .green, result: .wonAtShowdown)
                resultButton("Lost at Showdown", subtitle: "Lost at showdown", color: .red, result: .lostAtShowdown)
            }
        }
    }

    private func resultButton(_ title: String, subtitle: String, color: Color, result: PostflopResult) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectPostflopResult(result)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: color == .green ? "arrow.up.circle" : "arrow.down.circle")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Step 2b: C-Bet

    private var cBetStep: some View {
        VStack(spacing: 16) {
            Text("Continuation Bet?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Did you bet the flop after raising preflop?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                actionButton("Yes", color: .green) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectCBet(true)
                    }
                }

                actionButton("No", color: .red) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectCBet(false)
                    }
                }
            }
        }
    }

    // MARK: - Action Button

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(color, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
        }
    }
}
