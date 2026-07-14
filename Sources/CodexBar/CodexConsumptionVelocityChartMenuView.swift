import SwiftUI

@MainActor
struct CodexConsumptionVelocityChartMenuView: View {
    private enum Layout {
        static let chartHeight: CGFloat = 120
    }

    let velocity: CodexConsumptionVelocity
    let error: String?
    let width: CGFloat
    let now: Date

    var body: some View {
        VStack(alignment: .leading) {
            if self.velocity.points.isEmpty {
                Text(self.emptyStateText)
                    .font(.footnote)
                    .foregroundStyle(self.error == nil ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.chartHeight)
            } else {
                CodexConsumptionVelocityPlot(
                    points: self.velocity.points,
                    window: 24 * 60 * 60,
                    now: self.now)
                    .frame(height: Layout.chartHeight)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyStateText: String {
        if let error {
            return String(format: L("Consumption speed error: %@"), error)
        }
        return L("Measuring consumption speed…")
    }
}
