import Foundation
import LidopenCore
import ServiceManagement

private func sortMonitorRules(_ rules: [MonitorIdentity: MonitorRule]) -> [MonitorRule] {
    rules.values.sorted { $0.lastSeenName.localizedCaseInsensitiveCompare($1.lastSeenName) == .orderedAscending }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var appMode: AppMode
    @Published var launchAtLoginEnabled: Bool
    @Published var debugLoggingEnabled: Bool
    @Published var rules: [MonitorRule]
    @Published var pendingUnknownMonitors: [MonitorIdentity] = []
    @Published var snapshot: DisplaySnapshot?
    @Published var builtInDisabledByApp: Bool
    @Published var lastDecision: DisplayDecision = .noop(reason: "Not evaluated yet")
    @Published var lastErrorMessage: String?
    @Published var backendCapabilities = DisplayControlCapabilities(backendName: "Unknown", isAvailable: false, canDisableBuiltIn: false)
    @Published var logEntries: [EventLogger.Entry] = []

    private let settingsStore: SettingsStore
    private let controller: DisplayController
    private let logger: EventLogger
    private let loginItemManager = LoginItemManager()
    private let diagnosticsFormatter = AppDiagnosticsFormatter()

    init(settingsStore: SettingsStore, controller: DisplayController, logger: EventLogger) {
        self.settingsStore = settingsStore
        self.controller = controller
        self.logger = logger
        appMode = settingsStore.appMode
        launchAtLoginEnabled = settingsStore.launchAtLoginEnabled
        debugLoggingEnabled = settingsStore.debugLoggingEnabled
        rules = sortMonitorRules(settingsStore.monitorRules)
        builtInDisabledByApp = settingsStore.builtInDisabledByApp

        controller.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.apply(state: state)
            }
        }
    }

    func showSettings() {
        SettingsWindowController.shared.show(appModel: self)
    }

    func refresh() {
        controller.requestEvaluation(reason: "Manual refresh", debounce: false)
    }

    func manualDisable() {
        controller.manualDisableBuiltIn()
    }

    func manualRestore() {
        controller.manualRestoreBuiltIn()
    }

    func performPrimaryManualDisplayAction() {
        if builtInDisabledByApp {
            manualRestore()
        } else {
            manualDisable()
        }
    }

    func setAppMode(_ mode: AppMode) {
        appMode = mode
        settingsStore.appMode = mode
        controller.setAppMode(mode)
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLoginEnabled = isEnabled
        settingsStore.launchAtLoginEnabled = isEnabled
        loginItemManager.setEnabled(isEnabled)
        controller.setLaunchAtLoginEnabled(isEnabled)
    }

    func setDebugLoggingEnabled(_ isEnabled: Bool) {
        debugLoggingEnabled = isEnabled
        settingsStore.debugLoggingEnabled = isEnabled
        controller.setDebugLoggingEnabled(isEnabled)
        logEntries = logger.entries()
    }

    func saveRule(for identity: MonitorIdentity, preference: MonitorPreference) {
        controller.saveRule(for: identity, preference: preference)
    }

    func updateRule(_ rule: MonitorRule, preference: MonitorPreference) {
        controller.saveRule(for: rule.identity, preference: preference)
    }

    func deleteRule(_ rule: MonitorRule) {
        controller.deleteRule(for: rule.identity)
    }

    var diagnosticsText: String {
        diagnosticsFormatter.format(
            AppDiagnosticsSnapshot(
                appMode: appMode,
                builtInDisabledByApp: builtInDisabledByApp,
                backendCapabilities: backendCapabilities,
                lastErrorMessage: lastErrorMessage,
                snapshot: snapshot,
                pendingUnknownMonitors: pendingUnknownMonitors,
                rules: rules,
                logEntries: logEntries
            )
        )
    }

    var hasActiveExternalDisplay: Bool {
        snapshot?.activeExternalDisplays.isEmpty == false
    }

    // Restore must remain available even when no external display is present, otherwise
    // a manual disable could leave the user without an obvious recovery path.
    var canPerformPrimaryManualDisplayAction: Bool {
        builtInDisabledByApp || hasActiveExternalDisplay
    }

    var primaryManualDisplayActionTitle: String {
        builtInDisabledByApp ? "Restore Built-in Now" : "Disable Built-in Now"
    }

    var primaryManualDisplayActionSymbolName: String {
        builtInDisabledByApp ? "rectangle.on.rectangle" : "rectangle.slash"
    }

    private func apply(state: ControllerState) {
        snapshot = state.snapshot
        pendingUnknownMonitors = state.pendingUnknownMonitors
        builtInDisabledByApp = state.builtInDisabledByApp
        lastDecision = state.lastDecision
        lastErrorMessage = state.lastErrorMessage
        backendCapabilities = state.capabilities
        rules = sortMonitorRules(settingsStore.monitorRules)
        logEntries = logger.entries()
    }
}

@MainActor
private struct LoginItemManager {
    func setEnabled(_ isEnabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Personal sideload flow only; treat login-item registration as non-fatal.
        }
    }
}
