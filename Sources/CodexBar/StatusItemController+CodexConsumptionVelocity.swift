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
    func addCodexConsumptionVelocityMenuItemIfNeeded(
        to menu: NSMenu,
        provider: UsageProvider,
        width: CGFloat) -> Bool
    {
        guard provider == .codex, self.settings.historicalTrackingEnabled else { return false }
        let item = NSMenuItem(title: L("Consumption Speed"), action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = "codexConsumptionVelocitySubmenu"
        item.submenu = self.makeHostedSubviewPlaceholderMenu(
            chartID: Self.codexConsumptionVelocityChartID,
            provider: .codex,
            width: width)
        menu.addItem(item)
        return true
    }

    func appendCodexConsumptionVelocityChartItem(
        to submenu: NSMenu,
        width: CGFloat) -> Bool
    {
        if !self.menuCardRenderingEnabledForController {
            let chartItem = NSMenuItem()
            chartItem.isEnabled = true
            chartItem.representedObject = Self.codexConsumptionVelocityChartID
            chartItem.toolTip = UsageProvider.codex.rawValue
            submenu.addItem(chartItem)
            return true
        }

        let chartView = CodexConsumptionVelocityChartMenuView(
            velocity: self.store.codexConsumptionVelocity,
            error: self.store.codexConsumptionVelocityError,
            width: width,
            now: Date())
        let hosting = CodexConsumptionVelocityMenuHostingView(rootView: chartView)
        hosting.frame = NSRect(
            origin: .zero,
            size: NSSize(width: width, height: self.hostedSubviewFittingHeight(for: hosting, width: width)))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = true
        chartItem.representedObject = Self.codexConsumptionVelocityChartID
        chartItem.toolTip = UsageProvider.codex.rawValue
        submenu.addItem(chartItem)
        return true
    }

    func codexConsumptionVelocityRenderSignature() -> String {
        let velocity = self.store.codexConsumptionVelocity
        let values = [
            velocity.current?.multiplier,
            velocity.oneHour?.multiplier,
            velocity.twentyFourHours?.multiplier,
        ].map { value in
            value.map { String(format: "%.4f", $0) } ?? "nil"
        }.joined(separator: ":")
        return "\(self.store.codexConsumptionVelocityRevision)|\(values)|\(velocity.points.count)|" +
            (self.store.codexConsumptionVelocityError ?? "")
    }
}
