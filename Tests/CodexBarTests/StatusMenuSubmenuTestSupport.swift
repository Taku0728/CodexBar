import AppKit

extension NSMenu {
    func parentItemForTest(containingSubmenuItemID id: String) -> NSMenuItem? {
        self.items.first { item in
            item.submenu?.items.contains { ($0.representedObject as? String) == id } == true
        }
    }
}
