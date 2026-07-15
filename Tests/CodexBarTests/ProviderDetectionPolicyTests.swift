import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ProviderDetectionPolicyTests {
    @Test(arguments: [
        (completed: false, force: false, expected: true),
        (completed: false, force: true, expected: true),
        (completed: true, force: false, expected: false),
        (completed: true, force: true, expected: true),
    ])
    func `provider detection respects completion unless forced`(
        completed: Bool,
        force: Bool,
        expected: Bool)
    {
        #expect(ProviderDetectionPolicy.shouldRun(completed: completed, force: force) == expected)
    }

    @Test
    func `fresh install detects Codex and Claude Desktop without unconfigured Gemini`() {
        let enabled = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: true,
            claudeCLIInstalled: false,
            claudeDesktopInstalled: true,
            geminiCLIInstalled: true,
            geminiConfigured: false,
            antigravityAvailable: false))

        #expect(enabled == [.codex, .claude])
    }

    @Test
    func `configured Gemini CLI is detected`() {
        let enabled = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: false,
            claudeCLIInstalled: false,
            claudeDesktopInstalled: false,
            geminiCLIInstalled: true,
            geminiConfigured: true,
            antigravityAvailable: false))

        #expect(enabled == [.gemini])
    }

    @Test
    func `Codex remains the fallback when no provider source is available`() {
        let enabled = ProviderDetectionPolicy.enabledProviders(signals: .init(
            codexCLIInstalled: false,
            claudeCLIInstalled: false,
            claudeDesktopInstalled: false,
            geminiCLIInstalled: false,
            geminiConfigured: false,
            antigravityAvailable: false))

        #expect(enabled == [.codex])
    }
}
