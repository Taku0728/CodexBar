import AppKit
import CodexBarCore

extension StatusItemController {
    func addDetailsSubmenu(to menu: NSMenu, title: String, submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
    }

    func costHistoryMenuTitle() -> String {
        let days = self.store.settings.costUsageHistoryDays
        return days == 1 ? L("Usage history (today)") : String(format: L("Usage history (%d days)"), days)
    }
}
