import Foundation

public struct DisplayControllerTiming: Sendable {
    public let evaluationDebounceInterval: TimeInterval
    public let topologySettleInterval: TimeInterval
    public let failureRetryInterval: TimeInterval

    public init(
        evaluationDebounceInterval: TimeInterval = 0.75,
        topologySettleInterval: TimeInterval = 2.0,
        failureRetryInterval: TimeInterval = 10.0
    ) {
        self.evaluationDebounceInterval = evaluationDebounceInterval
        self.topologySettleInterval = topologySettleInterval
        self.failureRetryInterval = failureRetryInterval
    }
}

public final class DisplayController: @unchecked Sendable {
    public var onStateChange: (@Sendable (ControllerState) -> Void)?

    private let snapshotProvider: DisplaySnapshotProviding
    private let policy: DisplayPolicy
    private let backend: DisplayControlBackend
    private let settingsStore: SettingsStore
    private let logger: EventLogger
    private let scheduler: Scheduling
    private let timing: DisplayControllerTiming

    private var topologySettleUntil: Date?
    private var failureRetryAfter: Date?
    private var pendingEvaluation: ScheduledTask?
    private var restoreWatchdogTask: ScheduledTask?
    private var state: ControllerState
    private var lastKnownBuiltInDisplay: DisplayInfo?
    private var automaticEvaluationsAreSuspended = false

    public init(
        snapshotProvider: DisplaySnapshotProviding,
        policy: DisplayPolicy,
        backend: DisplayControlBackend,
        settingsStore: SettingsStore,
        logger: EventLogger,
        scheduler: Scheduling = DispatchScheduler(),
        timing: DisplayControllerTiming = DisplayControllerTiming()
    ) {
        self.snapshotProvider = snapshotProvider
        self.policy = policy
        self.backend = backend
        self.settingsStore = settingsStore
        self.logger = logger
        self.scheduler = scheduler
        self.timing = timing
        self.state = ControllerState(
            snapshot: nil,
            pendingUnknownMonitors: [],
            lastDecision: .noop(reason: "Not evaluated yet"),
            builtInDisabledByApp: settingsStore.builtInDisabledByApp,
            lastErrorMessage: nil,
            capabilities: DisplayControlCapabilities(
                backendName: "Unknown",
                isAvailable: false,
                canDisableBuiltIn: false
            )
        )
    }

    public func bootstrap() {
        requestEvaluation(reason: "App launch", debounce: false)
    }

    public func requestEvaluation(reason: String, debounce: Bool = true) {
        guard !automaticEvaluationsAreSuspended else {
            logger.info("Skipping evaluation while displays are sleeping: \(reason)")
            return
        }

        logger.info("Queueing evaluation: \(reason)")
        pendingEvaluation?.cancel()
        let settleTime = remainingTopologySettleTime()
        let delay = debounce ? max(timing.evaluationDebounceInterval, settleTime) : settleTime
        pendingEvaluation = scheduler.schedule(after: delay) { [weak self] in
            self?.evaluate(reason: reason)
        }
    }

    public func notifyWillSleep() {
        logger.info("System will sleep")
        suspendAutomaticEvaluations()
    }

    public func notifyDidWake() {
        logger.info("System did wake")
        resumeAutomaticEvaluations()
        topologySettleUntil = scheduler.now.addingTimeInterval(timing.topologySettleInterval)
        requestEvaluation(reason: "System wake", debounce: true)
    }

    public func notifyScreensDidSleep() {
        logger.info("Screens did sleep")
        suspendAutomaticEvaluations()
    }

    public func notifyScreensDidWake() {
        logger.info("Screens did wake")
        resumeAutomaticEvaluations()
        topologySettleUntil = scheduler.now.addingTimeInterval(timing.topologySettleInterval)
        requestEvaluation(reason: "Screens wake", debounce: true)
    }

    public func setAppMode(_ mode: AppMode) {
        settingsStore.appMode = mode
        requestEvaluation(reason: "App mode changed", debounce: false)
    }

    public func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        settingsStore.launchAtLoginEnabled = isEnabled
        publishCurrentState()
    }

    public func setDebugLoggingEnabled(_ isEnabled: Bool) {
        settingsStore.debugLoggingEnabled = isEnabled
        publishCurrentState()
    }

    public func saveRule(for identity: MonitorIdentity, preference: MonitorPreference) {
        var rules = settingsStore.monitorRules
        rules[identity] = MonitorRule(identity: identity, preference: preference, lastSeenName: identity.displayName)
        settingsStore.monitorRules = rules
        logger.info("Saved rule for \(identity.displayName): \(preference.displayName)")
        requestEvaluation(reason: "Saved monitor rule", debounce: false)
    }

    public func deleteRule(for identity: MonitorIdentity) {
        var rules = settingsStore.monitorRules
        rules.removeValue(forKey: identity)
        settingsStore.monitorRules = rules
        requestEvaluation(reason: "Deleted monitor rule", debounce: false)
    }

    public func manualDisableBuiltIn() {
        evaluate(reason: "Manual disable", forcedDecision: .disableBuiltIn)
    }

    public func manualRestoreBuiltIn() {
        evaluate(reason: "Manual restore", forcedDecision: .restoreBuiltIn)
    }

    public func currentState() -> ControllerState {
        state
    }

    public func prepareForTermination() {
        pendingEvaluation?.cancel()
        restoreWatchdogTask?.cancel()
        guard settingsStore.builtInDisabledByApp else {
            return
        }

        let snapshot = snapshotProvider.captureSnapshot()
        if snapshot.builtInDisplay != nil {
            reconcileBuiltInDisabledState(with: snapshot)
            publishCurrentState()
            return
        }

        let restoreSnapshot = restoreSnapshot(from: snapshot)
        guard restoreSnapshot.builtInDisplay != nil else {
            logger.error("App termination: unable to restore built-in display because no built-in display identity is available.")
            return
        }

        logger.info("App termination: attempting to restore built-in display.")
        executeBackendAction(description: "restore built-in on termination", snapshot: restoreSnapshot) {
            try backend.restoreBuiltIn(in: restoreSnapshot)
            settingsStore.builtInDisabledByApp = false
        }
    }

    private func remainingTopologySettleTime() -> TimeInterval {
        guard let topologySettleUntil else { return 0 }
        return max(0, topologySettleUntil.timeIntervalSince(scheduler.now))
    }

    private func remainingFailureRetryTime() -> TimeInterval {
        guard let failureRetryAfter else { return 0 }
        return max(0, failureRetryAfter.timeIntervalSince(scheduler.now))
    }

    private func suspendAutomaticEvaluations() {
        automaticEvaluationsAreSuspended = true
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        restoreWatchdogTask?.cancel()
        restoreWatchdogTask = nil
    }

    private func resumeAutomaticEvaluations() {
        automaticEvaluationsAreSuspended = false
    }

    private func evaluate(reason: String, forcedDecision: DisplayDecision? = nil) {
        let snapshot = snapshotProvider.captureSnapshot()
        if let builtInDisplay = snapshot.builtInDisplay {
            lastKnownBuiltInDisplay = builtInDisplay
        }
        reconcileBuiltInDisabledState(with: snapshot)
        let capabilities = backend.capabilities(for: snapshot)
        let evaluation = policy.evaluate(
            snapshot: snapshot,
            appMode: settingsStore.appMode,
            rules: settingsStore.monitorRules
        )

        let decision = resolvedDecision(
            for: snapshot,
            evaluation: evaluation,
            forcedDecision: forcedDecision
        )
        logger.info("Evaluating display state: \(reason)")

        state = ControllerState(
            snapshot: snapshot,
            pendingUnknownMonitors: evaluation.unknownMonitors,
            lastDecision: decision,
            builtInDisabledByApp: settingsStore.builtInDisabledByApp,
            lastErrorMessage: nil,
            capabilities: capabilities
        )
        publishCurrentState()
        defer { syncRestoreWatchdog() }

        guard shouldExecuteBackendAction(for: decision, forcedDecision: forcedDecision) else {
            return
        }

        if forcedDecision == nil {
            guard failureRetryAfter.map({ $0 <= scheduler.now }) ?? true else {
                logger.info("Skipping backend action during failure retry delay")
                return
            }
        }

        switch decision {
        case .disableBuiltIn:
            guard snapshot.builtInDisplay != nil, !snapshot.activeExternalDisplays.isEmpty else {
                logger.info("Skip disable: no safe external display topology")
                return
            }
            guard settingsStore.builtInDisabledByApp == false else {
                logger.info("Skip disable: already disabled by app")
                return
            }
            executeBackendAction(description: "disable built-in", snapshot: snapshot) {
                try backend.disableBuiltIn(in: snapshot)
                settingsStore.builtInDisabledByApp = true
            }

        case .restoreBuiltIn:
            let restoreSnapshot = restoreSnapshot(from: snapshot)
            guard restoreSnapshot.builtInDisplay != nil else {
                logger.info("Skip restore: no built-in display identity available")
                return
            }
            guard settingsStore.builtInDisabledByApp else {
                logger.info("Skip restore: built-in was not disabled by app")
                return
            }
            executeBackendAction(description: "restore built-in", snapshot: restoreSnapshot) {
                try backend.restoreBuiltIn(in: restoreSnapshot)
                settingsStore.builtInDisabledByApp = false
            }

        case let .promptForUnknownMonitor(monitors):
            logger.info("Unknown monitor(s) need a rule: \(monitors.map(\.displayName).joined(separator: ", "))")

        case let .noop(reason):
            logger.info("No action: \(reason)")
        }
    }

    private func executeBackendAction(
        description: String,
        snapshot: DisplaySnapshot,
        action: () throws -> Void
    ) {
        do {
            try action()
            failureRetryAfter = nil
            state = ControllerState(
                snapshot: snapshot,
                pendingUnknownMonitors: state.pendingUnknownMonitors,
                lastDecision: state.lastDecision,
                builtInDisabledByApp: settingsStore.builtInDisabledByApp,
                lastErrorMessage: nil,
                capabilities: backend.capabilities(for: snapshot)
            )
            logger.info("Backend action succeeded: \(description)")
        } catch {
            let message = error.localizedDescription
            logger.error("Backend action failed: \(description) - \(message)")
            failureRetryAfter = scheduler.now.addingTimeInterval(timing.failureRetryInterval)
            state = ControllerState(
                snapshot: snapshot,
                pendingUnknownMonitors: state.pendingUnknownMonitors,
                lastDecision: state.lastDecision,
                builtInDisabledByApp: settingsStore.builtInDisabledByApp,
                lastErrorMessage: message,
                capabilities: backend.capabilities(for: snapshot)
            )
        }
        publishCurrentState()
    }

    private func shouldExecuteBackendAction(
        for decision: DisplayDecision,
        forcedDecision: DisplayDecision?
    ) -> Bool {
        switch decision {
        case .disableBuiltIn:
            return forcedDecision != nil || settingsStore.appMode == .auto

        case .restoreBuiltIn:
            return forcedDecision != nil || settingsStore.builtInDisabledByApp

        case .promptForUnknownMonitor, .noop:
            return false
        }
    }

    private func resolvedDecision(
        for snapshot: DisplaySnapshot,
        evaluation: PolicyEvaluation,
        forcedDecision: DisplayDecision?
    ) -> DisplayDecision {
        if let forcedDecision {
            return forcedDecision
        }

        if shouldRestoreAppDisabledBuiltIn(from: snapshot) {
            return .restoreBuiltIn
        }

        return evaluation.decision
    }

    private func shouldRestoreAppDisabledBuiltIn(from snapshot: DisplaySnapshot) -> Bool {
        settingsStore.builtInDisabledByApp && snapshot.physicallyConnectedExternalDisplays.isEmpty
    }

    private func reconcileBuiltInDisabledState(with snapshot: DisplaySnapshot) {
        guard settingsStore.builtInDisabledByApp, snapshot.builtInDisplay != nil else {
            return
        }

        settingsStore.builtInDisabledByApp = false
        failureRetryAfter = nil
        logger.info("Built-in display is present again; clearing app-disabled state.")
    }

    private func syncRestoreWatchdog() {
        guard !automaticEvaluationsAreSuspended else {
            restoreWatchdogTask?.cancel()
            restoreWatchdogTask = nil
            return
        }

        if settingsStore.builtInDisabledByApp {
            guard restoreWatchdogTask == nil else {
                return
            }

            logger.info("Starting built-in restore watchdog.")
            let delay = max(timing.topologySettleInterval, remainingFailureRetryTime())
            restoreWatchdogTask = scheduler.schedule(after: delay) { [weak self] in
                guard let self else { return }
                self.restoreWatchdogTask = nil

                guard self.settingsStore.builtInDisabledByApp else {
                    return
                }

                self.evaluate(reason: "Built-in restore watchdog")
            }
            return
        }

        guard restoreWatchdogTask != nil else {
            return
        }

        restoreWatchdogTask?.cancel()
        restoreWatchdogTask = nil
        logger.info("Stopping built-in restore watchdog.")
    }

    private func restoreSnapshot(from snapshot: DisplaySnapshot) -> DisplaySnapshot {
        guard snapshot.builtInDisplay == nil, let lastKnownBuiltInDisplay else {
            return snapshot
        }

        return DisplaySnapshot(
            displays: [lastKnownBuiltInDisplay] + snapshot.displays,
            capturedAt: snapshot.capturedAt
        )
    }

    private func publishCurrentState() {
        onStateChange?(state)
    }
}
