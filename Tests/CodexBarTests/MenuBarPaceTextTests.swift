import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarPaceTextTests {
    private static func pace(deltaPercent: Double, stage: UsagePace.Stage) -> UsagePace {
        UsagePace(
            stage: stage,
            deltaPercent: deltaPercent,
            expectedUsedPercent: 50,
            actualUsedPercent: 50 + deltaPercent,
            etaSeconds: nil,
            willLastToReset: true)
    }

    @Test
    func `paceText drops the sign when the rounded delta is zero`() {
        let slightlyAhead = Self.pace(deltaPercent: 0.3, stage: .onTrack)
        let slightlyBehind = Self.pace(deltaPercent: -0.3, stage: .onTrack)

        // A sub-half-percent delta rounds to 0; "+0%" / "-0%" is a nonsensical signed zero.
        #expect(MenuBarDisplayText.paceText(pace: slightlyAhead) == "0%")
        #expect(MenuBarDisplayText.paceText(pace: slightlyBehind) == "0%")
    }

    @Test
    func `paceText keeps the sign for non-zero deltas`() {
        #expect(MenuBarDisplayText.paceText(pace: Self.pace(deltaPercent: 3, stage: .ahead)) == "+3%")
        #expect(MenuBarDisplayText.paceText(pace: Self.pace(deltaPercent: -3, stage: .behind)) == "-3%")
    }

    @Test
    func `consumption velocity text shows only the direction and multiplier`() {
        let fast = Self.velocity(multiplier: 2.4, confidence: .stable)
        let slowEstimate = Self.velocity(multiplier: 0.8, confidence: .estimated)

        #expect(MenuBarDisplayText.consumptionVelocityText(fast) == "↑2.4×")
        #expect(MenuBarDisplayText.consumptionVelocityText(slowEstimate) == "↓0.8×")
        #expect(MenuBarDisplayText.consumptionVelocityText(.measuring) == nil)
    }

    private static func velocity(
        multiplier: Double,
        confidence: CodexConsumptionVelocityConfidence) -> CodexConsumptionVelocity
    {
        CodexConsumptionVelocity(
            confidence: confidence,
            current: CodexConsumptionVelocityWindow(
                duration: 15 * 60,
                multiplier: multiplier,
                percentPerHour: 1,
                tokensPerMinute: 100),
            oneHour: nil,
            twentyFourHours: nil,
            exhaustionAt: nil,
            points: [],
            measuredAt: Date())
    }
}
