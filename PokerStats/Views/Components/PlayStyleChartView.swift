import SwiftUI

/// Diamond/radar chart showing player's style position.
/// X-axis: Tight↔Loose (derived from VPIP), Y-axis: Passive↔Aggressive (derived from PFR/VPIP ratio).
struct PlayStyleChartView: View {
    let vpip: Double? // 0.0–1.0
    let pfr: Double? // 0.0–1.0

    private let size: CGFloat = 250

    /// Normalized X position (0=tight, 1=loose) based on VPIP
    private var xPosition: CGFloat {
        guard let vpip else { return 0.5 }
        // VPIP 0–50% maps to 0–1
        return CGFloat(min(vpip / 0.50, 1.0))
    }

    /// Normalized Y position (0=passive, 1=aggressive) based on PFR/VPIP ratio
    private var yPosition: CGFloat {
        guard let vpip, let pfr, vpip > 0 else { return 0.5 }
        let ratio = pfr / vpip
        // Ratio 0–1 maps to 0–1
        return CGFloat(min(ratio, 1.0))
    }

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let halfSize = min(canvasSize.width, canvasSize.height) / 2 * 0.85

            // Draw concentric diamond rings
            for i in 1...4 {
                let scale = CGFloat(i) / 4.0
                let ringPath = diamondPath(center: center, size: halfSize * scale)
                context.stroke(ringPath, with: .color(.white.opacity(0.08)), lineWidth: 1)
            }

            // Draw axes
            let axisColor = Color.white.opacity(0.15)
            // Horizontal axis
            var hLine = Path()
            hLine.move(to: CGPoint(x: center.x - halfSize, y: center.y))
            hLine.addLine(to: CGPoint(x: center.x + halfSize, y: center.y))
            context.stroke(hLine, with: .color(axisColor), lineWidth: 1)
            // Vertical axis
            var vLine = Path()
            vLine.move(to: CGPoint(x: center.x, y: center.y - halfSize))
            vLine.addLine(to: CGPoint(x: center.x, y: center.y + halfSize))
            context.stroke(vLine, with: .color(axisColor), lineWidth: 1)

            // Draw quadrant zone fills
            drawQuadrantFills(context: context, center: center, halfSize: halfSize)

            // Draw player dot
            if vpip != nil && pfr != nil {
                let dotX = center.x + (xPosition - 0.5) * 2 * halfSize
                let dotY = center.y - (yPosition - 0.5) * 2 * halfSize

                // Glow
                let glowRect = CGRect(x: dotX - 12, y: dotY - 12, width: 24, height: 24)
                context.fill(Circle().path(in: glowRect), with: .color(.pokerAccent.opacity(0.3)))

                // Dot
                let dotRect = CGRect(x: dotX - 6, y: dotY - 6, width: 12, height: 12)
                context.fill(Circle().path(in: dotRect), with: .color(.pokerAccent))

                // Inner dot
                let innerRect = CGRect(x: dotX - 3, y: dotY - 3, width: 6, height: 6)
                context.fill(Circle().path(in: innerRect), with: .color(.white))
            }
        }
        .frame(width: size, height: size)
        .overlay(axisLabels)
    }

    // MARK: - Axis Labels

    private var axisLabels: some View {
        ZStack {
            // Top: Aggressive
            Text("Aggressive")
                .font(.caption2)
                .foregroundStyle(Color.pokerTextTertiary)
                .position(x: size / 2, y: 8)

            // Bottom: Passive
            Text("Passive")
                .font(.caption2)
                .foregroundStyle(Color.pokerTextTertiary)
                .position(x: size / 2, y: size - 8)

            // Left: Tight
            Text("Tight")
                .font(.caption2)
                .foregroundStyle(Color.pokerTextTertiary)
                .position(x: 16, y: size / 2)

            // Right: Loose
            Text("Loose")
                .font(.caption2)
                .foregroundStyle(Color.pokerTextTertiary)
                .position(x: size - 18, y: size / 2)

            // Quadrant labels
            Text("TAG")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.pokerProfit.opacity(0.6))
                .position(x: size * 0.30, y: size * 0.30)

            Text("LAG")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.orange.opacity(0.6))
                .position(x: size * 0.70, y: size * 0.30)

            Text("Rock")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.cyan.opacity(0.6))
                .position(x: size * 0.30, y: size * 0.70)

            Text("Fish")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.yellow.opacity(0.6))
                .position(x: size * 0.70, y: size * 0.70)
        }
    }

    // MARK: - Helpers

    private func diamondPath(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - size)) // top
        path.addLine(to: CGPoint(x: center.x + size, y: center.y)) // right
        path.addLine(to: CGPoint(x: center.x, y: center.y + size)) // bottom
        path.addLine(to: CGPoint(x: center.x - size, y: center.y)) // left
        path.closeSubpath()
        return path
    }

    private func drawQuadrantFills(context: GraphicsContext, center: CGPoint, halfSize: CGFloat) {
        // Top-left: TAG (green)
        var tagPath = Path()
        tagPath.move(to: center)
        tagPath.addLine(to: CGPoint(x: center.x, y: center.y - halfSize))
        tagPath.addLine(to: CGPoint(x: center.x - halfSize, y: center.y))
        tagPath.closeSubpath()
        context.fill(tagPath, with: .color(Color.pokerProfit.opacity(0.05)))

        // Top-right: LAG (orange)
        var lagPath = Path()
        lagPath.move(to: center)
        lagPath.addLine(to: CGPoint(x: center.x, y: center.y - halfSize))
        lagPath.addLine(to: CGPoint(x: center.x + halfSize, y: center.y))
        lagPath.closeSubpath()
        context.fill(lagPath, with: .color(Color.orange.opacity(0.05)))

        // Bottom-left: Rock (blue)
        var rockPath = Path()
        rockPath.move(to: center)
        rockPath.addLine(to: CGPoint(x: center.x - halfSize, y: center.y))
        rockPath.addLine(to: CGPoint(x: center.x, y: center.y + halfSize))
        rockPath.closeSubpath()
        context.fill(rockPath, with: .color(Color.cyan.opacity(0.05)))

        // Bottom-right: Fish (yellow)
        var fishPath = Path()
        fishPath.move(to: center)
        fishPath.addLine(to: CGPoint(x: center.x + halfSize, y: center.y))
        fishPath.addLine(to: CGPoint(x: center.x, y: center.y + halfSize))
        fishPath.closeSubpath()
        context.fill(fishPath, with: .color(Color.yellow.opacity(0.05)))
    }
}

#Preview {
    VStack {
        PlayStyleChartView(vpip: 0.22, pfr: 0.18) // TAG
        PlayStyleChartView(vpip: 0.45, pfr: 0.08) // Fish
        PlayStyleChartView(vpip: nil, pfr: nil)    // No data
    }
    .background(Color.pokerBackground)
    .preferredColorScheme(.dark)
}
