import Foundation

public struct CodexCLIAccountSnapshot: Sendable {
    public let usage: UsageSnapshot?
    public let credits: CreditsSnapshot?
    public let identity: ProviderIdentitySnapshot?

    public init(
        usage: UsageSnapshot?,
        credits: CreditsSnapshot?,
        identity: ProviderIdentitySnapshot? = nil)
    {
        self.usage = usage
        self.credits = credits
        self.identity = identity
    }
}

public struct CodexAccountTokenUsageSnapshot: Codable, Equatable, Sendable {
    public struct Summary: Codable, Equatable, Sendable {
        public let lifetimeTokens: Int64?
        public let currentStreakDays: Int64?
        public let longestRunningTurnSec: Int64?
        public let longestStreakDays: Int64?
        public let peakDailyTokens: Int64?

        public init(
            lifetimeTokens: Int64?,
            currentStreakDays: Int64? = nil,
            longestRunningTurnSec: Int64? = nil,
            longestStreakDays: Int64? = nil,
            peakDailyTokens: Int64? = nil)
        {
            self.lifetimeTokens = lifetimeTokens
            self.currentStreakDays = currentStreakDays
            self.longestRunningTurnSec = longestRunningTurnSec
            self.longestStreakDays = longestStreakDays
            self.peakDailyTokens = peakDailyTokens
        }
    }

    public struct DailyUsageBucket: Codable, Equatable, Sendable {
        public let startDate: String
        public let tokens: Int64

        public init(startDate: String, tokens: Int64) {
            self.startDate = startDate
            self.tokens = tokens
        }
    }

    public let summary: Summary
    public let dailyUsageBuckets: [DailyUsageBucket]?
    public let updatedAt: Date

    public init(
        summary: Summary,
        dailyUsageBuckets: [DailyUsageBucket]?,
        updatedAt: Date)
    {
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: CodingKey {
        case summary
        case dailyUsageBuckets
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = try container.decode(Summary.self, forKey: .summary)
        self.dailyUsageBuckets = try container.decodeIfPresent(
            [DailyUsageBucket].self,
            forKey: .dailyUsageBuckets)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct CodexCLIAccountTokenUsageSnapshot: Sendable {
    public let tokenUsage: CodexAccountTokenUsageSnapshot
    public let identity: ProviderIdentitySnapshot?

    public init(
        tokenUsage: CodexAccountTokenUsageSnapshot,
        identity: ProviderIdentitySnapshot?)
    {
        self.tokenUsage = tokenUsage
        self.identity = identity
    }
}
