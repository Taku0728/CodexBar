import SwiftUI

struct CodexConsumptionVelocityInlineView: View {
    let velocity: CodexConsumptionVelocity
    let error: String?
    let now: Date
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("Consumption Speed"))
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                if let summary = CodexConsumptionVelocityPresentation.summaryText(self.velocity) {
                    Text(summary)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(self.summaryColor)
                        .monospacedDigit()
                }
            }
            if !self.velocity.points.isEmpty {
                CodexConsumptionVelocityPlot(
                    points: self.velocity.points,
                    window: 60 * 60,
                    now: self.now)
                    .frame(height: 94)
            }
            HStack(spacing: 8) {
                self.metric(title: "15m", value: self.velocity.current)
                self.metric(title: "1h", value: self.velocity.oneHour)
                self.metric(title: "24h", value: self.velocity.twentyFourHours)
            }
            if let detail = self.detailText {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(self.error == nil
                        ? MenuHighlightStyle.secondary(self.isHighlighted)
                        : MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(self.isHighlighted ? 0.18 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(title: String, value: CodexConsumptionVelocityWindow?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            Text(value.map { self.multiplierText($0.multiplier) } ?? "—")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailText: String? {
        if let error {
            return String(format: L("Consumption speed error: %@"), error)
        }
        let projection = CodexConsumptionVelocityPresentation.projectionText(self.velocity, now: self.now)
        return self.velocity.confidence == .estimated
            ? "\(L("Estimated from quota changes")) · \(projection)"
            : projection
    }

    private func multiplierText(_ multiplier: Double) -> String {
        CodexConsumptionVelocityPresentation.multiplierText(
            multiplier,
            confidence: self.velocity.confidence)
    }

    private var summaryColor: Color {
        guard let multiplier = self.velocity.current?.multiplier else {
            return MenuHighlightStyle.secondary(self.isHighlighted)
        }
        return multiplier > 1.05 ? .orange : .green
    }
}
