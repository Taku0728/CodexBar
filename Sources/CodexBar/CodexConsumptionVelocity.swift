import Foundation

struct CodexConsumptionVelocitySample: Codable, Equatable, Sendable {
    let capturedAt: Date
    let lifetimeTokens: Int64
    let weeklyUsedPercent: Double
    let weeklyResetsAt: Date
}

enum CodexConsumptionVelocityConfidence: Equatable, Sendable {
    case measuring
    case estimated
    case stable
}

struct CodexConsumptionVelocityWindow: Equatable, Sendable {
    let duration: TimeInterval
    let multiplier: Double
    let percentPerHour: Double
    let tokensPerMinute: Double
}

struct CodexConsumptionVelocityPoint: Identifiable, Equatable, Sendable {
    let capturedAt: Date
    let multiplier: Double

    var id: Date {
        self.capturedAt
    }
}

struct CodexConsumptionVelocity: Equatable, Sendable {
    let confidence: CodexConsumptionVelocityConfidence
    let current: CodexConsumptionVelocityWindow?
    let oneHour: CodexConsumptionVelocityWindow?
    let twentyFourHours: CodexConsumptionVelocityWindow?
    let exhaustionAt: Date?
    let points: [CodexConsumptionVelocityPoint]
    let measuredAt: Date?

    static let measuring = Self(
        confidence: .measuring,
        current: nil,
        oneHour: nil,
        twentyFourHours: nil,
        exhaustionAt: nil,
        points: [],
        measuredAt: nil)
}

enum CodexConsumptionVelocityEvaluator {
    private static let currentWindow: TimeInterval = 15 * 60
    private static let oneHourWindow: TimeInterval = 60 * 60
    private static let twentyFourHourWindow: TimeInterval = 24 * 60 * 60
    private static let minimumCoverageRatio = 0.8
    private static let maximumSampleAge: TimeInterval = 5 * 60
    private static let chartPointInterval: TimeInterval = 5 * 60

    static func evaluate(
        samples: [CodexConsumptionVelocitySample],
        now: Date) -> CodexConsumptionVelocity
    {
        let segment = self.currentMonotonicSegment(samples: samples, now: now)
        guard let latest = segment.last,
              now.timeIntervalSince(latest.capturedAt) <= self.maximumSampleAge,
              latest.weeklyResetsAt > now,
              let calibration = self.calibration(samples: segment)
        else {
            return Self.measuringResult(measuredAt: segment.last?.capturedAt)
        }

        let remainingPercent = max(0, 100 - latest.weeklyUsedPercent)
        let remainingHours = latest.weeklyResetsAt.timeIntervalSince(now) / 3600
        guard remainingHours > 0 else {
            return Self.measuringResult(measuredAt: latest.capturedAt)
        }
        let sustainablePercentPerHour = remainingPercent / remainingHours
        guard sustainablePercentPerHour > 0 else {
            return Self.measuringResult(measuredAt: latest.capturedAt)
        }

        let current = self.window(
            duration: self.currentWindow,
            samples: segment,
            calibration: calibration.tokensPerPercent,
            sustainablePercentPerHour: sustainablePercentPerHour,
            endingAt: latest.capturedAt)
        let oneHour = self.window(
            duration: self.oneHourWindow,
            samples: segment,
            calibration: calibration.tokensPerPercent,
            sustainablePercentPerHour: sustainablePercentPerHour,
            endingAt: latest.capturedAt)
        let twentyFourHours = self.window(
            duration: self.twentyFourHourWindow,
            samples: segment,
            calibration: calibration.tokensPerPercent,
            sustainablePercentPerHour: sustainablePercentPerHour,
            endingAt: latest.capturedAt)

        let exhaustionAt = oneHour.flatMap { metric -> Date? in
            guard metric.percentPerHour > 0 else { return nil }
            let projected = now.addingTimeInterval(remainingPercent / metric.percentPerHour * 3600)
            return projected < latest.weeklyResetsAt ? projected : nil
        }
        let points = self.chartPoints(
            samples: segment,
            now: now,
            calibration: calibration.tokensPerPercent,
            sustainablePercentPerHour: sustainablePercentPerHour)

        return CodexConsumptionVelocity(
            confidence: calibration.percentDelta >= 3 ? .stable : .estimated,
            current: current,
            oneHour: oneHour,
            twentyFourHours: twentyFourHours,
            exhaustionAt: exhaustionAt,
            points: points,
            measuredAt: latest.capturedAt)
    }

    private struct Calibration {
        let tokensPerPercent: Double
        let percentDelta: Double
    }

    private static func calibration(samples: [CodexConsumptionVelocitySample]) -> Calibration? {
        guard let first = samples.first else { return nil }
        var minimum = first
        var best: Calibration?
        for sample in samples.dropFirst() {
            if sample.weeklyUsedPercent < minimum.weeklyUsedPercent {
                minimum = sample
                continue
            }
            let percentDelta = sample.weeklyUsedPercent - minimum.weeklyUsedPercent
            let tokenDelta = sample.lifetimeTokens - minimum.lifetimeTokens
            guard percentDelta >= 1, tokenDelta > 0 else { continue }
            let candidate = Calibration(
                tokensPerPercent: Double(tokenDelta) / percentDelta,
                percentDelta: percentDelta)
            if candidate.percentDelta > (best?.percentDelta ?? 0) {
                best = candidate
            }
        }
        return best
    }

    private static func chartPoints(
        samples: [CodexConsumptionVelocitySample],
        now: Date,
        calibration: Double,
        sustainablePercentPerHour: Double) -> [CodexConsumptionVelocityPoint]
    {
        let cutoff = now.addingTimeInterval(-self.twentyFourHourWindow)
        var startIndex = 0
        var lastPointAt = Date.distantPast
        var points: [CodexConsumptionVelocityPoint] = []

        for endIndex in samples.indices where samples[endIndex].capturedAt >= cutoff {
            let end = samples[endIndex]
            guard end.capturedAt.timeIntervalSince(lastPointAt) >= self.chartPointInterval
                || endIndex == samples.indices.last
            else { continue }

            let target = end.capturedAt.addingTimeInterval(-self.currentWindow)
            while startIndex + 1 < endIndex, samples[startIndex + 1].capturedAt <= target {
                startIndex += 1
            }
            let start = samples[startIndex]
            let elapsed = end.capturedAt.timeIntervalSince(start.capturedAt)
            let tokenDelta = end.lifetimeTokens - start.lifetimeTokens
            guard elapsed >= self.currentWindow * self.minimumCoverageRatio,
                  tokenDelta >= 0
            else { continue }

            let tokensPerMinute = Double(tokenDelta) / (elapsed / 60)
            let percentPerHour = tokensPerMinute * 60 / calibration
            points.append(CodexConsumptionVelocityPoint(
                capturedAt: end.capturedAt,
                multiplier: percentPerHour / sustainablePercentPerHour))
            lastPointAt = end.capturedAt
        }
        return points
    }

    private static func window(
        duration: TimeInterval,
        samples: [CodexConsumptionVelocitySample],
        calibration: Double,
        sustainablePercentPerHour: Double,
        endingAt: Date) -> CodexConsumptionVelocityWindow?
    {
        guard let end = samples.last(where: { $0.capturedAt <= endingAt }) else { return nil }
        let target = end.capturedAt.addingTimeInterval(-duration)
        guard let start = samples.last(where: { $0.capturedAt <= target }) ?? samples.first,
              end.capturedAt.timeIntervalSince(start.capturedAt) >= duration * self.minimumCoverageRatio
        else { return nil }

        let elapsed = end.capturedAt.timeIntervalSince(start.capturedAt)
        let tokenDelta = end.lifetimeTokens - start.lifetimeTokens
        guard elapsed > 0, tokenDelta >= 0 else { return nil }
        let tokensPerMinute = Double(tokenDelta) / (elapsed / 60)
        let percentPerHour = tokensPerMinute * 60 / calibration
        return CodexConsumptionVelocityWindow(
            duration: duration,
            multiplier: percentPerHour / sustainablePercentPerHour,
            percentPerHour: percentPerHour,
            tokensPerMinute: tokensPerMinute)
    }

    private static func currentMonotonicSegment(
        samples: [CodexConsumptionVelocitySample],
        now: Date) -> [CodexConsumptionVelocitySample]
    {
        let sorted = samples
            .filter { $0.capturedAt <= now }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard let latest = sorted.last else { return [] }

        var segment: [CodexConsumptionVelocitySample] = []
        for sample in sorted.reversed() {
            guard sample.weeklyResetsAt == latest.weeklyResetsAt else { break }
            if let next = segment.last,
               sample.lifetimeTokens > next.lifetimeTokens
               || sample.weeklyUsedPercent > next.weeklyUsedPercent
            {
                break
            }
            segment.append(sample)
        }
        return segment.reversed()
    }

    private static func measuringResult(measuredAt: Date?) -> CodexConsumptionVelocity {
        CodexConsumptionVelocity(
            confidence: .measuring,
            current: nil,
            oneHour: nil,
            twentyFourHours: nil,
            exhaustionAt: nil,
            points: [],
            measuredAt: measuredAt)
    }
}

private struct CodexConsumptionVelocityDocument: Codable, Sendable {
    let version: Int
    var accounts: [String: [CodexConsumptionVelocitySample]]
}

struct CodexConsumptionVelocityStore: Sendable {
    private static let schemaVersion = 1
    private static let retention: TimeInterval = 8 * 24 * 60 * 60
    private static let denseRetention: TimeInterval = 24 * 60 * 60
    let fileURL: URL?

    init(fileURL: URL? = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func samples(for accountKey: String) throws -> [CodexConsumptionVelocitySample] {
        try self.load().accounts[accountKey] ?? []
    }

    func append(_ sample: CodexConsumptionVelocitySample, accountKey: String) throws
        -> [CodexConsumptionVelocitySample]
    {
        guard !accountKey.isEmpty else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        guard let fileURL else { return [sample] }

        var document = try self.load()
        let cutoff = sample.capturedAt.addingTimeInterval(-Self.retention)
        var samples = (document.accounts[accountKey] ?? []).filter { $0.capturedAt >= cutoff }
        if let latest = samples.last, latest.capturedAt == sample.capturedAt {
            samples[samples.count - 1] = sample
        } else {
            samples.append(sample)
        }
        samples.sort { $0.capturedAt < $1.capturedAt }
        samples = Self.compacted(samples, now: sample.capturedAt)
        document.accounts[accountKey] = samples

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
        return samples
    }

    private func load() throws -> CodexConsumptionVelocityDocument {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return CodexConsumptionVelocityDocument(version: Self.schemaVersion, accounts: [:])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(
            CodexConsumptionVelocityDocument.self,
            from: Data(contentsOf: fileURL))
        guard document.version == Self.schemaVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    private static func compacted(
        _ samples: [CodexConsumptionVelocitySample],
        now: Date) -> [CodexConsumptionVelocitySample]
    {
        let denseCutoff = now.addingTimeInterval(-self.denseRetention)
        var hourly: [Int64: CodexConsumptionVelocitySample] = [:]
        var dense: [CodexConsumptionVelocitySample] = []
        for sample in samples {
            if sample.capturedAt >= denseCutoff {
                dense.append(sample)
            } else {
                let hour = Int64(sample.capturedAt.timeIntervalSince1970 / 3600)
                hourly[hour] = sample
            }
        }
        return hourly.values.sorted { $0.capturedAt < $1.capturedAt } + dense
    }

    private static func defaultFileURL() -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
        else { return nil }
        return root
            .appendingPathComponent("com.steipete.codexbar", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent("codex-consumption-velocity.json", isDirectory: false)
    }
}
