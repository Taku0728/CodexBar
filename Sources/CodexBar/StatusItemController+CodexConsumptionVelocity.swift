import AppKit
import CodexBarCore
import SwiftUI

private final class CodexConsumptionVelocityMenuHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool {
        true
    }
}

extension StatusItemController {
    @discardableResult
    func addConsumptionVelocityMenuItemIfNeeded(
        to menu: NSMenu,
        provider: UsageProvider,
        width: CGFloat) -> Bool
    {
        guard self.consumptionVelocityTrackingEnabled(for: provider) else { return false }
        let item = NSMenuItem(title: "\(L("Consumption Speed")) · 24h", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = "consumptionVelocitySubmenu"
        item.submenu = self.makeHostedSubviewPlaceholderMenu(
            chartID: Self.consumptionVelocityChartID,
            provider: provider,
            width: width)
        menu.addItem(item)
        return true
    }

    func appendConsumptionVelocityChartItem(
        to submenu: NSMenu,
        provider: UsageProvider,
        width: CGFloat) -> Bool
    {
        guard let state = self.consumptionVelocityState(for: provider) else { return false }
        if !self.menuCardRenderingEnabledForController {
            let chartItem = NSMenuItem()
            chartItem.isEnabled = true
            chartItem.representedObject = Self.consumptionVelocityChartID
            chartItem.toolTip = provider.rawValue
            submenu.addItem(chartItem)
            return true
        }

        let chartView = CodexConsumptionVelocityChartMenuView(
            velocity: state.velocity,
            error: state.error,
            width: width,
            now: Date())
        let hosting = CodexConsumptionVelocityMenuHostingView(rootView: chartView)
        hosting.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: self.hostedSubviewFittingHeight(for: hosting, width: width)))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = true
        chartItem.representedObject = Self.consumptionVelocityChartID
        chartItem.toolTip = provider.rawValue
        submenu.addItem(chartItem)
        return true
    }

    func consumptionVelocityRenderSignature(for provider: UsageProvider) -> String {
        guard let state = self.consumptionVelocityState(for: provider) else { return "disabled" }
        let velocity = state.velocity
        let values = [
            velocity.current?.multiplier,
            velocity.oneHour?.multiplier,
            velocity.twentyFourHours?.multiplier,
        ].map { value in
            value.map { String(format: "%.4f", $0) } ?? "nil"
        }.joined(separator: ":")
        return "\(state.revision)|\(values)|\(velocity.points.count)|" + (state.error ?? "")
    }

    private func consumptionVelocityTrackingEnabled(for provider: UsageProvider) -> Bool {
        switch provider {
        case .codex:
            self.settings.codexConsumptionVelocityTrackingEnabled
        case .claude:
            self.settings.claudeConsumptionVelocityTrackingEnabled
        default:
            false
        }
    }

    private func consumptionVelocityState(for provider: UsageProvider)
        -> (velocity: CodexConsumptionVelocity, error: String?, revision: Int)?
    {
        guard self.consumptionVelocityTrackingEnabled(for: provider) else { return nil }
        return switch provider {
        case .codex:
            (
                self.store.codexConsumptionVelocity,
                self.store.codexConsumptionVelocityError,
                self.store.codexConsumptionVelocityRevision)
        case .claude:
            (
                self.store.claudeConsumptionVelocity,
                self.store.claudeConsumptionVelocityError,
                self.store.claudeConsumptionVelocityRevision)
        default:
            nil
        }
    }
}
