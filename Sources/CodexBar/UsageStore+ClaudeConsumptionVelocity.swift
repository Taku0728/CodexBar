import CodexBarCore
import Foundation

enum ClaudeConsumptionVelocityRefreshError: LocalizedError {
    case missingQuotaWindow
    case unresolvedAccount

    var errorDescription: String? {
        switch self {
        case .missingQuotaWindow:
            "Claude did not return a weekly or 5-hour usage window with a reset time."
        case .unresolvedAccount:
            "Claude usage could not be tied safely to the active account."
        }
    }
}

extension UsageStore {
    private nonisolated static let claudeConsumptionVelocityMinimumFetchInterval: TimeInterval = 55

    func refreshConsumptionVelocityAfterProviderRefresh(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        claudeOAuthHistoryOwnerIdentifier: String?,
        isClaudeOAuthSample: Bool,
        generation: UInt64?) async
    {
        switch provider {
        case .codex:
            self.recordCodexHistoricalSampleIfNeeded(snapshot: snapshot)
            await self.refreshCodexConsumptionVelocity(snapshot: snapshot, generation: generation)
        case .claude:
            await self.refreshClaudeConsumptionVelocity(
                snapshot: snapshot,
                accountKey: self.claudeConsumptionVelocityAccountKey(
                    oauthHistoryOwnerIdentifier: claudeOAuthHistoryOwnerIdentifier,
                    isOAuthSample: isClaudeOAuthSample),
                generation: generation)
        default:
            break
        }
    }

    func refreshClaudeConsumptionVelocity(
        snapshot: UsageSnapshot,
        accountKey: String?,
        generation: UInt64?,
        now: Date = Date()) async
    {
        guard self.settings.claudeConsumptionVelocityTrackingEnabled else {
            self.claudeConsumptionVelocity = .measuring
            self.claudeConsumptionVelocityError = nil
            self.displayedClaudeConsumptionVelocityAccountKey = nil
            self.claudeConsumptionVelocityRevision &+= 1
            return
        }

        guard let accountKey, !accountKey.isEmpty else {
            self.claudeConsumptionVelocity = .measuring
            self.claudeConsumptionVelocityError = ClaudeConsumptionVelocityRefreshError.unresolvedAccount
                .localizedDescription
            self.displayedClaudeConsumptionVelocityAccountKey = nil
            self.claudeConsumptionVelocityRevision &+= 1
            return
        }

        let accountChanged = self.displayedClaudeConsumptionVelocityAccountKey != accountKey
        if accountChanged {
            self.claudeConsumptionVelocity = .measuring
            self.claudeConsumptionVelocityError = nil
            self.displayedClaudeConsumptionVelocityAccountKey = accountKey
            self.claudeConsumptionVelocityRevision &+= 1
        }
        if !accountChanged,
           let lastFetch = self.lastClaudeConsumptionVelocityFetchAtByAccount[accountKey],
           now.timeIntervalSince(lastFetch) < Self.claudeConsumptionVelocityMinimumFetchInterval
        {
            return
        }
        self.lastClaudeConsumptionVelocityFetchAtByAccount[accountKey] = now

        do {
            let quota = try Self.claudeVelocityWindow(snapshot: snapshot)
            let sample = CodexConsumptionVelocitySample(
                capturedAt: now,
                weeklyUsedPercent: quota.usedPercent,
                weeklyResetsAt: quota.resetsAt,
                quotaWindowMinutes: quota.windowMinutes)
            let store = self.claudeConsumptionVelocityStore ?? CodexConsumptionVelocityStore(
                fileURL: Self.claudeConsumptionVelocityFileURL())
            let samples = try await Task.detached(priority: .utility) {
                try store.append(sample, accountKey: accountKey)
            }.value
            guard self.isCurrentProviderRefreshGeneration(.claude, generation: generation) else { return }
            guard self.displayedClaudeConsumptionVelocityAccountKey == accountKey else { return }
            self.claudeConsumptionVelocity = CodexConsumptionVelocityEvaluator.evaluate(
                samples: samples,
                now: now)
            self.claudeConsumptionVelocityError = nil
            self.claudeConsumptionVelocityRevision &+= 1
        } catch {
            guard !Task.isCancelled else { return }
            guard self.isCurrentProviderRefreshGeneration(.claude, generation: generation) else { return }
            guard self.displayedClaudeConsumptionVelocityAccountKey == accountKey else { return }
            self.claudeConsumptionVelocity = .measuring
            self.claudeConsumptionVelocityError = error.localizedDescription
            self.claudeConsumptionVelocityRevision &+= 1
        }
    }

    private nonisolated static func claudeVelocityWindow(snapshot: UsageSnapshot) throws
        -> (usedPercent: Double, resetsAt: Date, windowMinutes: Int)
    {
        let baseWindows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
        let windows = baseWindows + (snapshot.extraRateWindows?.filter(\.usageKnown).map(\.window) ?? [])
        let validWindows = windows.filter { window in
            !window.isSyntheticPlaceholder
                && window.usedPercent.isFinite
                && (0...100).contains(window.usedPercent)
                && window.resetsAt != nil
        }
        let weekly = validWindows.first { window in
            guard let minutes = window.windowMinutes else { return false }
            return (10070...10090).contains(minutes)
        }
        let fiveHour = validWindows.first { window in
            guard let minutes = window.windowMinutes else { return false }
            return (290...310).contains(minutes)
        }
        guard let selected = weekly ?? fiveHour,
              let resetsAt = selected.resetsAt,
              let windowMinutes = selected.windowMinutes
        else {
            throw ClaudeConsumptionVelocityRefreshError.missingQuotaWindow
        }
        return (selected.usedPercent, resetsAt, windowMinutes)
    }

    private func claudeConsumptionVelocityAccountKey(
        oauthHistoryOwnerIdentifier: String?,
        isOAuthSample: Bool) -> String?
    {
        if isOAuthSample {
            guard let oauthHistoryOwnerIdentifier else { return nil }
            let normalized = oauthHistoryOwnerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.count == 64,
                  normalized.unicodeScalars.allSatisfy({ scalar in
                      (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
                  })
            else { return nil }
            return "__claude_velocity_oauth__:\(normalized)"
        }
        return self.planUtilizationHistorySelection(for: .claude).accountKey
    }

    private nonisolated static func claudeConsumptionVelocityFileURL() -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
        else { return nil }
        return root
            .appendingPathComponent("com.steipete.codexbar", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
            .appendingPathComponent("claude-consumption-velocity.json", isDirectory: false)
    }
}
