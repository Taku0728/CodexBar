import Charts
import SwiftUI

@MainActor
struct CodexConsumptionVelocityChartMenuView: View {
    private enum Layout {
        static let chartHeight: CGFloat = 120
        static let safePace = 1.0
    }

    let velocity: CodexConsumptionVelocity
    let error: String?
    let width: CGFloat
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.metrics
            if self.velocity.points.isEmpty {
                Text(self.emptyStateText)
                    .font(.footnote)
                    .foregroundStyle(self.error == nil ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.chartHeight)
            } else {
                self.chart
                    .frame(height: Layout.chartHeight)
                Text(self.projectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .topLeading)
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            self.metric(title: "15m", value: self.velocity.current)
            self.metric(title: "1h", value: self.velocity.oneHour)
            self.metric(title: "24h", value: self.velocity.twentyFourHours)
        }
    }

    private func metric(title: String, value: CodexConsumptionVelocityWindow?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { Self.multiplierText($0.multiplier) } ?? "—")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        let yMaximum = max(3, (self.velocity.points.map(\.multiplier).max() ?? 1) * 1.15)
        return Chart {
            ForEach(self.velocity.points) { point in
                AreaMark(
                    x: .value("Time", point.capturedAt),
                    y: .value("Speed", point.multiplier))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.25), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom))
                LineMark(
                    x: .value("Time", point.capturedAt),
                    y: .value("Speed", point.multiplier))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            RuleMark(y: .value(L("Safe pace"), Layout.safePace))
                .foregroundStyle(.green.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text(L("Safe pace"))
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
        }
        .chartYScale(domain: 0...yMaximum)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let multiplier = value.as(Double.self) {
                        Text(Self.multiplierText(multiplier))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel(L("Consumption Speed"))
    }

    private var emptyStateText: String {
        if let error {
            return String(format: L("Consumption speed error: %@"), error)
        }
        return L("Measuring consumption speed…")
    }

    private var projectionText: String {
        guard self.velocity.oneHour != nil else {
            return L("Measuring consumption speed…")
        }
        let projection: String = if let exhaustionAt = self.velocity.exhaustionAt {
            String(
                format: L("Runs out in %@ at the 1h pace"),
                Self.durationText(exhaustionAt.timeIntervalSince(self.now)))
        } else {
            L("The 1h pace stays within the reset")
        }
        if self.velocity.confidence == .estimated {
            return "\(L("Estimated from quota changes")) · \(projection)"
        }
        return projection
    }

    private static func multiplierText(_ multiplier: Double) -> String {
        String(format: "%.1f×", multiplier)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(duration / 60)))
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = Int(ceil(Double(minutes) / 60))
        if hours < 48 {
            return "\(hours)h"
        }
        return "\(Int(ceil(Double(hours) / 24)))d"
    }
}
