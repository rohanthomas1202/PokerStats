import ActivityKit
import SwiftUI
import WidgetKit

struct PokerStatsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.handCount)", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startTime, style: .timer)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.stakes)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("Invested", systemImage: "dollarsign.circle")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("$\(Int(context.state.totalInvested))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.attributes.startTime, style: .timer)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(width: 56)
            } minimal: {
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            // Left: stakes and location
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.stakes)
                    .font(.headline)
                    .fontWeight(.bold)
                if !context.attributes.location.isEmpty {
                    Text(context.attributes.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Center: hands
            VStack(spacing: 2) {
                Text("\(context.state.handCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Hands")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Right: timer and invested
            VStack(alignment: .trailing, spacing: 4) {
                Text(context.attributes.startTime, style: .timer)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)
                Text("$\(Int(context.state.totalInvested)) in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.8))
    }
}
