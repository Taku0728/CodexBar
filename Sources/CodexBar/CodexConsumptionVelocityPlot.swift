import Charts
import SwiftUI

struct CodexConsumptionVelocityPlot: View {
    private static let safePace = 1.0

    let points: [CodexConsumptionVelocityPoint]
    let window: TimeInterval
    let now: Date

    var body: some View {
        let visiblePoints = self.visiblePoints
        Chart {
            ForEach(visiblePoints) { point in
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
                if point.id == visiblePoints.last?.id {
                    PointMark(
                        x: .value("Time", point.capturedAt),
                        y: .value("Speed", point.multiplier))
                        .foregroundStyle(.blue)
                        .symbolSize(24)
                }
            }
            RuleMark(y: .value(L("Safe pace"), Self.safePace))
                .foregroundStyle(.green.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("\(L("Safe pace")) 1×")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
        }
        .chartXScale(domain: self.xDomain)
        .chartYScale(domain: 0...self.yMaximum)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let multiplier = value.as(Double.self) {
                        Text(CodexConsumptionVelocityPresentation.multiplierText(multiplier))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(self.axisLabel(for: date))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel(L("Consumption Speed"))
    }

    private var xDomain: ClosedRange<Date> {
        self.now.addingTimeInterval(-self.window)...self.now
    }

    private var yMaximum: Double {
        max(3, (self.visiblePoints.map(\.multiplier).max() ?? 1) * 1.15)
    }

    private var duration: TimeInterval {
        self.window
    }

    private var visiblePoints: [CodexConsumptionVelocityPoint] {
        let start = self.now.addingTimeInterval(-self.window)
        return self.points.filter { $0.capturedAt >= start && $0.capturedAt <= self.now }
    }

    private func axisLabel(for date: Date) -> String {
        if self.duration < 2 * 60 * 60 {
            return date.formatted(.dateTime.hour().minute())
        }
        if self.duration < 24 * 60 * 60 {
            return date.formatted(.dateTime.hour())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour())
    }
}

enum CodexConsumptionVelocityPresentation {
    static func multiplierText(
        _ multiplier: Double,
        confidence: CodexConsumptionVelocityConfidence? = nil) -> String
    {
        let estimate = confidence == .estimated ? "≈" : ""
        return String(format: "\(estimate)%.1f×", multiplier)
    }

    static func summaryText(_ velocity: CodexConsumptionVelocity) -> String? {
        guard let current = velocity.current else { return nil }
        let direction = if current.multiplier > 1.05 {
            "↑"
        } else if current.multiplier < 0.95 {
            "↓"
        } else {
            "→"
        }
        return "\(direction) \(self.multiplierText(current.multiplier, confidence: velocity.confidence))"
    }

    static func projectionText(_ velocity: CodexConsumptionVelocity, now: Date) -> String {
        guard velocity.current != nil else {
            return L("Measuring consumption speed…")
        }
        let basis = velocity.oneHour == nil ? "15m" : "1h"
        if let exhaustionAt = velocity.exhaustionAt {
            let duration = self.durationText(exhaustionAt.timeIntervalSince(now))
            return "\(basis) · \(String(format: L("Runs out in %@"), duration))"
        }
        return "\(basis) · \(L("Lasts until reset"))"
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(duration / 60)))
        if minutes < 60 { return "\(minutes)m" }
        let hours = Int(ceil(Double(minutes) / 60))
        if hours < 48 { return "\(hours)h" }
        return "\(Int(ceil(Double(hours) / 24)))d"
    }
}
