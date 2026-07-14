import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexConsumptionVelocityTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test
    func `quota calibration is required before publishing velocity`() {
        let reset = self.now.addingTimeInterval(100 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(minutesAgo: 15, tokens: 100_000, used: 10, reset: reset),
                self.sample(minutesAgo: 0, tokens: 110_000, used: 10, reset: reset),
            ],
            now: self.now)

        #expect(result.confidence == .measuring)
        #expect(result.current == nil)
    }

    @Test
    func `bootstrap calibration publishes the current speed after the first refresh interval`() throws {
        let reset = self.now.addingTimeInterval(100 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(
                    minutesAgo: 1,
                    tokens: 500_000,
                    localTokens: 100_000,
                    used: 10,
                    reset: reset),
                self.sample(
                    minutesAgo: 0,
                    tokens: 500_000,
                    localTokens: 110_000,
                    used: 10,
                    reset: reset),
            ],
            now: self.now,
            bootstrapTokensPerPercent: 1_000_000)

        #expect(result.confidence == .estimated)
        #expect(try #require(result.current).tokensPerMinute == 10000)
        #expect(try #require(result.current).multiplier > 0.66)
        #expect(try #require(result.current).multiplier < 0.67)
        #expect(result.points.count == 1)
    }

    @Test
    func `small reset timestamp drift stays in the same measurement segment`() throws {
        let reset = self.now.addingTimeInterval(100 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(
                    minutesAgo: 1,
                    tokens: 500_000,
                    localTokens: 100_000,
                    used: 10,
                    reset: reset),
                self.sample(
                    minutesAgo: 0,
                    tokens: 500_000,
                    localTokens: 110_000,
                    used: 10,
                    reset: reset.addingTimeInterval(-1)),
            ],
            now: self.now,
            bootstrapTokensPerPercent: 1_000_000)

        #expect(try #require(result.current).tokensPerMinute == 10000)
    }

    @Test
    func `current window projects exhaustion until the one hour window is available`() throws {
        let reset = self.now.addingTimeInterval(100 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(
                    minutesAgo: 1,
                    tokens: 500_000,
                    localTokens: 100_000,
                    used: 90,
                    reset: reset),
                self.sample(
                    minutesAgo: 0,
                    tokens: 500_000,
                    localTokens: 110_000,
                    used: 90,
                    reset: reset),
            ],
            now: self.now,
            bootstrapTokensPerPercent: 100_000)

        #expect(result.oneHour == nil)
        #expect(try #require(result.exhaustionAt) < reset)
    }

    @Test
    func `bootstrap estimate uses only local token days inside the active weekly period`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let reset = self.now.addingTimeInterval(5 * 24 * 3600)
        let weeklyStart = reset.addingTimeInterval(-7 * 24 * 3600)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 700,
            sessionCostUSD: nil,
            last30DaysTokens: 1900,
            last30DaysCostUSD: nil,
            daily: [
                self.dailyEntry(
                    date: formatter.string(from: weeklyStart.addingTimeInterval(-24 * 3600)),
                    tokens: 900),
                self.dailyEntry(date: formatter.string(from: weeklyStart), tokens: 300),
                self.dailyEntry(date: formatter.string(from: self.now), tokens: 700),
            ],
            updatedAt: self.now)

        let estimate = try #require(CodexConsumptionVelocityBootstrap.estimate(
            tokenSnapshot: snapshot,
            weeklyUsedPercent: 10,
            weeklyResetsAt: reset,
            now: self.now,
            calendar: calendar))

        #expect(estimate.weeklyTokens == 1000)
        #expect(estimate.tokensPerPercent == 100)
    }

    @Test
    func `short burst is visible before it materially changes the weekly pace`() throws {
        let reset = self.now.addingTimeInterval(100 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(minutesAgo: 120, tokens: 90000, used: 7, reset: reset),
                self.sample(minutesAgo: 60, tokens: 100_000, used: 8, reset: reset),
                self.sample(minutesAgo: 15, tokens: 110_000, used: 9, reset: reset),
                self.sample(minutesAgo: 0, tokens: 120_000, used: 10, reset: reset),
            ],
            now: self.now)

        #expect(result.confidence == .stable)
        #expect(try #require(result.current).multiplier > 4.4)
        #expect(try #require(result.current).multiplier < 4.5)
        #expect(try #require(result.oneHour).multiplier > 2.2)
        #expect(try #require(result.oneHour).multiplier < 2.3)
        #expect(result.twentyFourHours == nil)
        #expect(try #require(result.exhaustionAt).timeIntervalSince(self.now) == 45 * 3600)
    }

    @Test
    func `reset boundary prevents old quota samples from calibrating the new period`() {
        let oldReset = self.now.addingTimeInterval(-60)
        let newReset = self.now.addingTimeInterval(7 * 24 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(minutesAgo: 30, tokens: 100_000, used: 99, reset: oldReset),
                self.sample(minutesAgo: 15, tokens: 110_000, used: 0, reset: newReset),
                self.sample(minutesAgo: 0, tokens: 120_000, used: 0, reset: newReset),
            ],
            now: self.now)

        #expect(result.confidence == .measuring)
        #expect(result.current == nil)
    }

    @Test
    func `counter regression starts a new measurement segment`() {
        let reset = self.now.addingTimeInterval(7 * 24 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(minutesAgo: 30, tokens: 200_000, used: 5, reset: reset),
                self.sample(minutesAgo: 15, tokens: 10000, used: 6, reset: reset),
                self.sample(minutesAgo: 0, tokens: 20000, used: 6, reset: reset),
            ],
            now: self.now)

        #expect(result.confidence == .measuring)
        #expect(result.current == nil)
    }

    @Test
    func `stale samples are not presented as the current speed`() {
        let reset = self.now.addingTimeInterval(7 * 24 * 3600)
        let result = CodexConsumptionVelocityEvaluator.evaluate(
            samples: [
                self.sample(minutesAgo: 30, tokens: 90000, used: 7, reset: reset),
                self.sample(minutesAgo: 20, tokens: 100_000, used: 8, reset: reset),
                self.sample(minutesAgo: 10, tokens: 110_000, used: 9, reset: reset),
            ],
            now: self.now)

        #expect(result.confidence == .measuring)
        #expect(result.current == nil)
    }

    @Test
    func `store isolates account histories and retains the latest sample`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-velocity-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexConsumptionVelocityStore(
            fileURL: directory.appendingPathComponent("history.json", isDirectory: false))
        let reset = self.now.addingTimeInterval(7 * 24 * 3600)
        let first = self.sample(minutesAgo: 1, tokens: 100, used: 1, reset: reset)
        let second = self.sample(minutesAgo: 0, tokens: 200, used: 2, reset: reset)

        _ = try store.append(first, accountKey: "account-a")
        let accountA = try store.append(second, accountKey: "account-a")
        _ = try store.append(first, accountKey: "account-b")

        #expect(accountA == [first, second])
        #expect(try store.samples(for: "account-b") == [first])
    }

    @Test
    func `store compacts samples older than one day to hourly resolution`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-velocity-compaction-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexConsumptionVelocityStore(
            fileURL: directory.appendingPathComponent("history.json", isDirectory: false))
        let reset = self.now.addingTimeInterval(7 * 24 * 3600)
        let oldHour = floor(self.now.addingTimeInterval(-30 * 3600).timeIntervalSince1970 / 3600) * 3600
        let oldFirst = CodexConsumptionVelocitySample(
            capturedAt: Date(timeIntervalSince1970: oldHour + 60),
            lifetimeTokens: 100,
            weeklyUsedPercent: 1,
            weeklyResetsAt: reset)
        let oldLatest = CodexConsumptionVelocitySample(
            capturedAt: Date(timeIntervalSince1970: oldHour + 120),
            lifetimeTokens: 200,
            weeklyUsedPercent: 2,
            weeklyResetsAt: reset)
        let current = self.sample(minutesAgo: 0, tokens: 300, used: 3, reset: reset)

        _ = try store.append(oldFirst, accountKey: "account")
        _ = try store.append(oldLatest, accountKey: "account")
        let samples = try store.append(current, accountKey: "account")

        #expect(samples == [oldLatest, current])
    }

    private func sample(
        minutesAgo: Double,
        tokens: Int64,
        localTokens: Int64? = nil,
        used: Double,
        reset: Date) -> CodexConsumptionVelocitySample
    {
        CodexConsumptionVelocitySample(
            capturedAt: self.now.addingTimeInterval(-minutesAgo * 60),
            lifetimeTokens: tokens,
            localTokens: localTokens,
            weeklyUsedPercent: used,
            weeklyResetsAt: reset)
    }

    private func dailyEntry(date: String, tokens: Int) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            costUSD: nil,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }
}
