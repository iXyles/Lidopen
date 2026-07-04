import AppKit
import CoreGraphics
import Foundation
import LidopenCore

@MainActor
final class DisplayEventMonitor {
    fileprivate let controller: DisplayController
    private var isStarted = false
    private var workspaceObservers: [Any] = []

    init(controller: DisplayController) {
        self.controller = controller
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        registerDisplayCallback()
        registerWorkspaceNotifications()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    private func registerDisplayCallback() {
        CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func registerWorkspaceNotifications() {
        observeWorkspaceNotification(
            forName: NSWorkspace.willSleepNotification,
            action: { $0.notifyWillSleep() }
        )
        observeWorkspaceNotification(
            forName: NSWorkspace.didWakeNotification,
            action: { $0.notifyDidWake() }
        )
        observeWorkspaceNotification(
            forName: NSWorkspace.screensDidSleepNotification,
            action: { $0.notifyScreensDidSleep() }
        )
        observeWorkspaceNotification(
            forName: NSWorkspace.screensDidWakeNotification,
            action: { $0.notifyScreensDidWake() }
        )
        observeWorkspaceNotification(forName: NSWorkspace.sessionDidBecomeActiveNotification) { controller in
            controller.requestEvaluation(reason: "Session became active", debounce: true)
        }
    }

    private func observeWorkspaceNotification(
        forName name: NSNotification.Name,
        action: @escaping @Sendable (DisplayController) -> Void
    ) {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            action(self.controller)
        }
        workspaceObservers.append(observer)
    }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
    guard let userInfo else { return }
    let monitor = Unmanaged<DisplayEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    guard !flags.contains(.beginConfigurationFlag) else { return }

    // CoreGraphics can invoke this callback off the main thread. Funnel state changes
    // back through the main actor because the monitor and app model are UI-owned.
    DispatchQueue.main.async {
        monitor.controller.requestEvaluation(reason: "Display reconfiguration", debounce: true)
    }
}
