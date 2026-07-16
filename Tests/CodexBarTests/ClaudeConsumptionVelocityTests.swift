import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ClaudeConsumptionVelocityTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @MainActor
    @Test
    func `weekly quota is preferred over the 5-hour quota`() async throws {
        let fixture = self.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let weeklyReset = self.now.addingTimeInterval(4 * 24 * 60 * 60)
        let sessionReset = self.now.addingTimeInterval(3 * 60 * 60)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(
                sessionUsed: 10,
                sessionReset: sessionReset,
                weeklyUsed: 20,
                weeklyReset: weeklyReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now.addingTimeInterval(-15 * 60))
        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(
                sessionUsed: 80,
                sessionReset: sessionReset,
                weeklyUsed: 22,
                weeklyReset: weeklyReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now)

        let samples = try fixture.velocityStore.samples(for: "claude-account")
        #expect(samples.map(\.weeklyUsedPercent) == [20, 22])
        #expect(samples.allSatisfy { $0.weeklyResetsAt == weeklyReset })
        #expect(fixture.usageStore.claudeConsumptionVelocity.current != nil)
    }

    @MainActor
    @Test
    func `5-hour quota is used when weekly quota is unavailable`() async throws {
        let fixture = self.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let sessionReset = self.now.addingTimeInterval(3 * 60 * 60)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: sessionReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now.addingTimeInterval(-15 * 60))
        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 12, sessionReset: sessionReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now)

        let samples = try fixture.velocityStore.samples(for: "claude-account")
        #expect(samples.map(\.weeklyUsedPercent) == [10, 12])
        #expect(samples.allSatisfy { $0.weeklyResetsAt == sessionReset })
        #expect(fixture.usageStore.claudeConsumptionVelocity.current != nil)
        #expect(fixture.usageStore.claudeConsumptionVelocity.twentyFourHours == nil)
    }

    @MainActor
    @Test
    func `unresolved account never writes an unscoped history`() async throws {
        let fixture = self.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(
                sessionUsed: 10,
                sessionReset: self.now.addingTimeInterval(3 * 60 * 60)),
            accountKey: nil,
            generation: nil,
            now: self.now)

        #expect(try fixture.velocityStore.samples(for: "") == [])
        #expect(fixture.usageStore.claudeConsumptionVelocity == .measuring)
        #expect(fixture.usageStore.claudeConsumptionVelocityError != nil)
    }

    @MainActor
    @Test
    func `switching accounts immediately replaces the previous account velocity`() async {
        let fixture = self.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reset = self.now.addingTimeInterval(4 * 24 * 60 * 60)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: reset, weeklyUsed: 20, weeklyReset: reset),
            accountKey: "account-a",
            generation: nil,
            now: self.now.addingTimeInterval(-15 * 60))
        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: reset, weeklyUsed: 22, weeklyReset: reset),
            accountKey: "account-a",
            generation: nil,
            now: self.now)
        #expect(fixture.usageStore.claudeConsumptionVelocity.current != nil)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: reset, weeklyUsed: 5, weeklyReset: reset),
            accountKey: "account-b",
            generation: nil,
            now: self.now.addingTimeInterval(10))

        #expect(fixture.usageStore.displayedClaudeConsumptionVelocityAccountKey == "account-b")
        #expect(fixture.usageStore.claudeConsumptionVelocity.current == nil)
        #expect(fixture.usageStore.claudeConsumptionVelocity.points.isEmpty)
        #expect(fixture.usageStore.claudeConsumptionVelocity.measuredAt == self.now.addingTimeInterval(10))
        #expect(fixture.usageStore.claudeConsumptionVelocityError == nil)
    }

    @MainActor
    @Test
    func `an unresolved account clears a previously measured velocity`() async {
        let fixture = self.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reset = self.now.addingTimeInterval(4 * 24 * 60 * 60)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: reset, weeklyUsed: 20, weeklyReset: reset),
            accountKey: "account-a",
            generation: nil,
            now: self.now.addingTimeInterval(-15 * 60))
        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: reset, weeklyUsed: 22, weeklyReset: reset),
            accountKey: "account-a",
            generation: nil,
            now: self.now)
        #expect(fixture.usageStore.claudeConsumptionVelocity.current != nil)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 10, sessionReset: reset, weeklyUsed: 22, weeklyReset: reset),
            accountKey: nil,
            generation: nil,
            now: self.now.addingTimeInterval(10))

        #expect(fixture.usageStore.displayedClaudeConsumptionVelocityAccountKey == nil)
        #expect(fixture.usageStore.claudeConsumptionVelocity == .measuring)
        #expect(fixture.usageStore.claudeConsumptionVelocityError != nil)
    }

    @MainActor
    @Test
    func `switching from weekly to 5-hour quota starts a new measurement segment`() async throws {
        let fixture = self.makeStore()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let sharedReset = self.now.addingTimeInterval(3 * 60 * 60)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(
                sessionUsed: 30,
                sessionReset: sharedReset,
                weeklyUsed: 20,
                weeklyReset: sharedReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now.addingTimeInterval(-15 * 60))
        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(
                sessionUsed: 32,
                sessionReset: sharedReset,
                weeklyUsed: 22,
                weeklyReset: sharedReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now)
        #expect(fixture.usageStore.claudeConsumptionVelocity.current != nil)

        await fixture.usageStore.refreshClaudeConsumptionVelocity(
            snapshot: self.snapshot(sessionUsed: 40, sessionReset: sharedReset),
            accountKey: "claude-account",
            generation: nil,
            now: self.now.addingTimeInterval(60))

        let samples = try fixture.velocityStore.samples(for: "claude-account")
        #expect(samples.map(\.quotaWindowMinutes) == [7 * 24 * 60, 7 * 24 * 60, 5 * 60])
        #expect(fixture.usageStore.claudeConsumptionVelocity.current == nil)
        #expect(fixture.usageStore.claudeConsumptionVelocity.measuredAt == self.now.addingTimeInterval(60))
    }

    @MainActor
    @Test
    func `Claude consumption velocity tracking is enabled by default`() {
        let suite = "ClaudeConsumptionVelocityDefaultsTests-\(UUID().uuidString)"
        let settings = testSettingsStore(suiteName: suite)

        #expect(settings.claudeConsumptionVelocityTrackingEnabled)
        #expect(ClaudeProviderDescriptor.descriptor.metadata.defaultEnabled)
    }

    @MainActor
    private func makeStore() -> (
        usageStore: UsageStore,
        velocityStore: CodexConsumptionVelocityStore,
        directory: URL)
    {
        let suite = "ClaudeConsumptionVelocityTests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        let velocityStore = CodexConsumptionVelocityStore(
            fileURL: directory.appendingPathComponent("history.json"))
        let settings = testSettingsStore(suiteName: suite)
        let usageStore = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            claudeConsumptionVelocityStore: velocityStore,
            startupBehavior: .testing)
        return (usageStore, velocityStore, directory)
    }

    private func snapshot(
        sessionUsed: Double,
        sessionReset: Date,
        weeklyUsed: Double? = nil,
        weeklyReset: Date? = nil) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: sessionUsed,
                windowMinutes: 5 * 60,
                resetsAt: sessionReset,
                resetDescription: nil),
            secondary: weeklyUsed.map { used in
                RateWindow(
                    usedPercent: used,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: weeklyReset,
                    resetDescription: nil)
            },
            updatedAt: self.now)
    }
}
