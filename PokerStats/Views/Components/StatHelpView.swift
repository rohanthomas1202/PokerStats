import SwiftUI

// MARK: - Stat Definition

enum StatDefinition: String, CaseIterable, Identifiable {
    case vpip
    case pfr
    case cBet
    case wtsd
    case wsd
    case foldTo3Bet
    case foldPercent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vpip: "VPIP"
        case .pfr: "PFR"
        case .cBet: "C-Bet %"
        case .wtsd: "WTSD %"
        case .wsd: "W$SD %"
        case .foldTo3Bet: "Fold to 3-Bet %"
        case .foldPercent: "Fold %"
        }
    }

    var explanation: String {
        switch self {
        case .vpip:
            "Voluntarily Put money In Pot. The percentage of hands where you voluntarily put money in preflop (call or raise). Excludes posting blinds."
        case .pfr:
            "Pre-Flop Raise percentage. How often you raise before the flop. A key indicator of aggression."
        case .cBet:
            "Continuation Bet percentage. How often you bet the flop after raising preflop. Shows follow-through aggression."
        case .wtsd:
            "Went To ShowDown percentage. Of hands that saw the flop, how often you reached showdown. Indicates calling tendencies."
        case .wsd:
            "Won money at ShowDown. Of hands that went to showdown, how often you won. Measures hand selection quality."
        case .foldTo3Bet:
            "How often you fold when facing a 3-bet (re-raise) after you raised. High values mean you're exploitable."
        case .foldPercent:
            "Overall fold percentage. How often you fold preflop. Very high values indicate overly tight play."
        }
    }

    var idealRange: String {
        switch self {
        case .vpip: "18–28%"
        case .pfr: "14–22%"
        case .cBet: "55–75%"
        case .wtsd: "25–35%"
        case .wsd: "50–60%"
        case .foldTo3Bet: "40–60%"
        case .foldPercent: "70–85%"
        }
    }

    var goodRange: ClosedRange<Double> {
        switch self {
        case .vpip: 0.18...0.28
        case .pfr: 0.14...0.22
        case .cBet: 0.55...0.75
        case .wtsd: 0.25...0.35
        case .wsd: 0.50...0.60
        case .foldTo3Bet: 0.40...0.60
        case .foldPercent: 0.70...0.85
        }
    }
}

// MARK: - Help Button

struct StatHelpButton: View {
    let definition: StatDefinition
    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(Color.pokerTextTertiary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isShowingHelp) {
            statHelpSheet
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
    }

    private var statHelpSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(definition.title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    isShowingHelp = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(definition.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "target")
                    .foregroundStyle(Color.pokerProfit)
                Text("Ideal range: \(definition.idealRange)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .pokerCard()

            Spacer()
        }
        .padding()
        .background(Color.pokerBackground.ignoresSafeArea())
    }
}
