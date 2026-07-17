import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ClaudeCookieDefaultsTests {
    @MainActor
    @Test
    func `defaults browser cookie access to disabled`() throws {
        let suite = "ClaudeCookieDefaultsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suite)

        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.claudeUsageDataSource == .auto)
        #expect(store.claudeCookieSource == .off)

        store.claudeCookieSource = .auto

        #expect(store.claudeCookieSource == .auto)
    }
}
