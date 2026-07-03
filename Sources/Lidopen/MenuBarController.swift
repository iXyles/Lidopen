import AppKit
import Combine
import LidopenCore

@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appModel: AppModel
    private var cancellable: AnyCancellable?

    init(appModel: AppModel) {
        self.appModel = appModel
        configureStatusButton()
        cancellable = appModel.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            // ObservableObject emits before the @Published values are mutated. Rebuild on the
            // next main-queue turn so menu enablement reflects the updated state.
            DispatchQueue.main.async {
                self?.rebuildMenu()
            }
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        updateStatusButton()
        statusItem.menu = makeMenu()
    }

    // NSMenu is managed imperatively, so the simplest way to keep it in sync with the
    // observable app state is to rebuild it from a few small section builders.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addStatusSection(to: menu)
        addBehaviorSection(to: menu)
        addDisplaysSection(to: menu)
        addPendingMonitorSection(to: menu)
        addActionsSection(to: menu)
        return menu
    }

    private func addStatusSection(to menu: NSMenu) {
        let titleItem = NSMenuItem(title: "Lidopen", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let summaryItem = NSMenuItem(title: statusSummary, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(NSMenuItem.separator())
    }

    private func addBehaviorSection(to menu: NSMenu) {
        let behaviorHeader = NSMenuItem(title: "Behavior", action: nil, keyEquivalent: "")
        behaviorHeader.isEnabled = false
        menu.addItem(behaviorHeader)

        let manualModeItem = actionItem(title: "Manual Mode", action: #selector(setManualMode))
        manualModeItem.state = appModel.appMode == .manual ? .on : .off
        let autoModeItem = actionItem(title: "Auto Mode", action: #selector(setAutoMode))
        autoModeItem.state = appModel.appMode == .auto ? .on : .off
        menu.addItem(manualModeItem)
        menu.addItem(autoModeItem)
        menu.addItem(NSMenuItem.separator())
    }

    private func addDisplaysSection(to menu: NSMenu) {
        if let snapshot = appModel.snapshot {
            let displaysHeader = NSMenuItem(title: "Connected Displays", action: nil, keyEquivalent: "")
            displaysHeader.isEnabled = false
            menu.addItem(displaysHeader)

            for display in snapshot.displays {
                let suffix = display.isBuiltIn ? "built-in" : "external"
                let title = "\(display.name) (\(suffix))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.image = NSImage(
                    systemSymbolName: display.isBuiltIn ? "laptopcomputer" : "display",
                    accessibilityDescription: nil
                )
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }
    }

    private func addPendingMonitorSection(to menu: NSMenu) {
        for identity in appModel.pendingUnknownMonitors {
            let parent = NSMenuItem(title: "Choose behavior for \(identity.displayName)", action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
            let submenu = NSMenu()

            let disable = actionItem(title: "Always disable built-in", action: #selector(saveDisableRule(_:)))
            disable.representedObject = identity
            submenu.addItem(disable)

            let keep = actionItem(title: "Always keep built-in active", action: #selector(saveKeepRule(_:)))
            keep.representedObject = identity
            submenu.addItem(keep)

            menu.setSubmenu(submenu, for: parent)
            menu.addItem(parent)
        }

        if !appModel.pendingUnknownMonitors.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
    }

    private func addActionsSection(to menu: NSMenu) {
        let actionsHeader = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        actionsHeader.isEnabled = false
        menu.addItem(actionsHeader)

        let primaryAction = actionItem(
            title: appModel.primaryManualDisplayActionTitle,
            action: #selector(performPrimaryDisplayAction),
            symbolName: appModel.primaryManualDisplayActionSymbolName
        )
        primaryAction.isEnabled = appModel.canPerformPrimaryManualDisplayAction
        menu.addItem(primaryAction)

        menu.addItem(actionItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",", symbolName: "gearshape"))
        menu.addItem(actionItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
    }

    private var statusSummary: String {
        let externalCount = appModel.snapshot?.displays.filter { !$0.isBuiltIn }.count ?? 0
        let mode = appModel.appMode.displayName
        let builtIn = appModel.builtInDisabledByApp ? "built-in off" : "built-in on"
        if externalCount == 0 {
            return "\(mode) • no externals • \(builtIn)"
        }
        let label = externalCount == 1 ? "external" : "externals"
        return "\(mode) • \(externalCount) \(label) • \(builtIn)"
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.image = statusImage()
        button.toolTip = statusTooltip
        button.setAccessibilityTitle("Lidopen")
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = statusImage()
        button.toolTip = statusTooltip
    }

    private var statusTooltip: String {
        var parts = ["Lidopen", statusSummary]
        if !appModel.pendingUnknownMonitors.isEmpty {
            parts.append("Unknown monitor rule pending")
        }
        if appModel.lastErrorMessage != nil {
            parts.append("Last action failed")
        }
        return parts.joined(separator: "\n")
    }

    private func statusImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let color = NSColor.labelColor
        color.setStroke()
        color.setFill()

        let externalRect = NSRect(x: 8.5, y: 8.5, width: 7.0, height: 4.8)
        let externalPath = NSBezierPath(roundedRect: externalRect, xRadius: 1.2, yRadius: 1.2)
        externalPath.lineWidth = 1.6
        externalPath.stroke()

        let externalStand = NSBezierPath()
        externalStand.move(to: NSPoint(x: 11.8, y: 8.4))
        externalStand.line(to: NSPoint(x: 11.8, y: 6.5))
        externalStand.move(to: NSPoint(x: 10.0, y: 6.0))
        externalStand.line(to: NSPoint(x: 13.6, y: 6.0))
        externalStand.lineWidth = 1.4
        externalStand.stroke()

        let lidPath = NSBezierPath()
        lidPath.move(to: NSPoint(x: 3.2, y: 6.2))
        lidPath.line(to: NSPoint(x: 7.0, y: 10.6))
        lidPath.lineWidth = 1.8
        lidPath.lineCapStyle = .round
        lidPath.stroke()

        let basePath = NSBezierPath()
        basePath.move(to: NSPoint(x: 2.4, y: 4.6))
        basePath.line(to: NSPoint(x: 7.9, y: 4.6))
        basePath.line(to: NSPoint(x: 7.1, y: 3.2))
        basePath.line(to: NSPoint(x: 3.0, y: 3.2))
        basePath.close()
        basePath.lineWidth = 1.4
        basePath.stroke()

        if appModel.builtInDisabledByApp {
            let offSlash = NSBezierPath()
            offSlash.move(to: NSPoint(x: 2.9, y: 10.8))
            offSlash.line(to: NSPoint(x: 6.8, y: 6.8))
            offSlash.lineWidth = 1.8
            offSlash.lineCapStyle = .round
            offSlash.stroke()
        }

        if !appModel.pendingUnknownMonitors.isEmpty {
            let badge = NSBezierPath(ovalIn: NSRect(x: 13.0, y: 12.2, width: 3.0, height: 3.0))
            badge.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String = "", symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func setManualMode() {
        appModel.setAppMode(.manual)
    }

    @objc private func setAutoMode() {
        appModel.setAppMode(.auto)
    }

    @objc private func performPrimaryDisplayAction() {
        appModel.performPrimaryManualDisplayAction()
    }

    @objc private func refresh() {
        appModel.refresh()
    }

    @objc private func openSettings() {
        appModel.showSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func saveDisableRule(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? MonitorIdentity else { return }
        appModel.saveRule(for: identity, preference: .disableBuiltIn)
    }

    @objc private func saveKeepRule(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? MonitorIdentity else { return }
        appModel.saveRule(for: identity, preference: .keepBuiltIn)
    }
}
