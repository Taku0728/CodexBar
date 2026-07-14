import CodexBarCore
import Foundation

enum CodexConsumptionVelocityRefreshError: LocalizedError {
    case missingWeeklyWindow
    case missingLifetimeTokens
    case unresolvedAccount
    case accountMismatch(expected: String, actual: String)
    case ambiguousAccount

    var errorDescription: String? {
        switch self {
        case .missingWeeklyWindow:
            "Codex did not return a weekly usage window with a reset time."
        case .missingLifetimeTokens:
            "Codex did not return cumulative token usage."
        case .unresolvedAccount:
            "Codex token usage could not be tied to the active account."
        case let .accountMismatch(expected, actual):
            "Codex token usage belongs to \(actual), not the active account \(expected)."
        case .ambiguousAccount:
            "Codex token usage is paused because multiple accounts cannot be distinguished safely."
        }
    }
}

extension UsageStore {
    private nonisolated static let codexConsumptionVelocityMinimumFetchInterval: TimeInterval = 55

    func refreshCodexConsumptionVelocity(
        snapshot: UsageSnapshot,
        generation: UInt64?,
        now: Date = Date()) async
    {
        guard self.settings.historicalTrackingEnabled else {
            self.codexConsumptionVelocity = .measuring
            self.codexConsumptionVelocityError = nil
            self.codexConsumptionVelocityRevision &+= 1
            return
        }
        let store = self.codexConsumptionVelocityStore ?? CodexConsumptionVelocityStore()
        if let lastFetch = self.lastCodexConsumptionVelocityFetchAt,
           now.timeIntervalSince(lastFetch) < Self.codexConsumptionVelocityMinimumFetchInterval
        {
            return
        }
        self.lastCodexConsumptionVelocityFetchAt = now

        do {
            let weekly = try Self.codexWeeklyVelocityWindow(snapshot: snapshot)
            guard let expectedEmail = CodexIdentityResolver.normalizeEmail(
                snapshot.accountEmail(for: .codex))
            else {
                throw CodexConsumptionVelocityRefreshError.unresolvedAccount
            }
            let ownership = self.codexOwnershipContext(preferredEmail: expectedEmail, snapshot: snapshot)
            guard !ownership.hasAdjacentEmailScopeAmbiguity,
                  !ownership.hasAdjacentMultiAccountVeto
            else {
                throw CodexConsumptionVelocityRefreshError.ambiguousAccount
            }
            guard let accountKey = ownership.canonicalKey else {
                throw CodexConsumptionVelocityRefreshError.unresolvedAccount
            }

            let environment = ProviderRegistry.makeEnvironment(
                base: self.environmentBase,
                provider: .codex,
                settings: self.settings,
                tokenOverride: nil)
            let fetcher = ProviderRegistry.makeFetcher(
                base: self.codexFetcher,
                provider: .codex,
                env: environment)
            let accountUsage = try await fetcher.loadAccountTokenUsage()
            guard self.isCurrentProviderRefreshGeneration(.codex, generation: generation) else { return }
            guard let actualEmail = CodexIdentityResolver.normalizeEmail(
                accountUsage.identity?.accountEmail)
            else {
                throw CodexConsumptionVelocityRefreshError.unresolvedAccount
            }
            guard actualEmail == expectedEmail else {
                throw CodexConsumptionVelocityRefreshError.accountMismatch(
                    expected: expectedEmail,
                    actual: actualEmail)
            }
            guard let lifetimeTokens = accountUsage.tokenUsage.summary.lifetimeTokens,
                  lifetimeTokens >= 0
            else {
                throw CodexConsumptionVelocityRefreshError.missingLifetimeTokens
            }

            let sample = CodexConsumptionVelocitySample(
                capturedAt: now,
                lifetimeTokens: lifetimeTokens,
                weeklyUsedPercent: weekly.usedPercent,
                weeklyResetsAt: weekly.resetsAt)
            let samples = try await Task.detached(priority: .utility) {
                try store.append(sample, accountKey: accountKey)
            }.value
            guard self.isCurrentProviderRefreshGeneration(.codex, generation: generation) else { return }
            self.codexConsumptionVelocity = CodexConsumptionVelocityEvaluator.evaluate(
                samples: samples,
                now: now)
            self.codexConsumptionVelocityError = nil
            self.codexConsumptionVelocityRevision &+= 1
        } catch {
            guard !Task.isCancelled else { return }
            guard self.isCurrentProviderRefreshGeneration(.codex, generation: generation) else { return }
            self.codexConsumptionVelocityError = error.localizedDescription
            self.codexConsumptionVelocityRevision &+= 1
        }
    }

    private nonisolated static func codexWeeklyVelocityWindow(snapshot: UsageSnapshot) throws
        -> (usedPercent: Double, resetsAt: Date)
    {
        let baseWindows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
        let windows = baseWindows + (snapshot.extraRateWindows?.map(\.window) ?? [])
        guard let weekly = windows.first(where: { window in
            guard let minutes = window.windowMinutes else { return false }
            return (10070...10090).contains(minutes)
        }), let resetsAt = weekly.resetsAt else {
            throw CodexConsumptionVelocityRefreshError.missingWeeklyWindow
        }
        return (weekly.usedPercent, resetsAt)
    }
}
