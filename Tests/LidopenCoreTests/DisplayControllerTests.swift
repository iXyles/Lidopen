import Foundation
import LidopenCore
import Testing

@Test func duplicateEventsCollapseIntoOneEvaluation() {
    let scheduler = TestScheduler()
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        monitorRules: [.sample(name: "Home"): MonitorRule(identity: .sample(name: "Home"), preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let snapshotProvider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: .sample(name: "Home"))]))
    let controller = DisplayController(
        snapshotProvider: snapshotProvider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 1.0,
            topologySettleInterval: 2.0,
            failureRetryInterval: 5.0
        )
    )

    controller.requestEvaluation(reason: "one")
    controller.requestEvaluation(reason: "two")
    scheduler.advance(by: 1.0)

    #expect(backend.disableCalls == 1)
}

@Test func topologySettleDelaySuppressesPrematureToggle() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let snapshotProvider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)]))
    let controller = DisplayController(
        snapshotProvider: snapshotProvider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 1.0,
            topologySettleInterval: 5.0,
            failureRetryInterval: 5.0
        )
    )

    controller.notifyDidWake()
    scheduler.advance(by: 1.0)
    #expect(backend.disableCalls == 0)

    scheduler.advance(by: 4.0)
    #expect(backend.disableCalls == 1)
}

@Test func backendFailureDoesNotRetryAggressively() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend(failDisable: true)
    let store = InMemorySettingsStore(
        appMode: .auto,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let controller = DisplayController(
        snapshotProvider: FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)])),
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "first")
    scheduler.advance(by: 0.5)
    controller.requestEvaluation(reason: "second")
    scheduler.advance(by: 0.5)

    #expect(backend.disableCalls == 1)
}

@Test func manualDisableBypassesFailureCooldown() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend(failDisable: true)
    let store = InMemorySettingsStore(
        appMode: .auto,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let controller = DisplayController(
        snapshotProvider: FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)])),
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "auto")
    scheduler.advance(by: 0.5)
    #expect(backend.disableCalls == 1)

    controller.manualDisableBuiltIn()
    #expect(backend.disableCalls == 2)
}

@Test func disconnectAfterDisableRestoresBuiltIn() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        builtInDisabledByApp: true,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn()]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "disconnect")
    scheduler.advance(by: 0.5)

    #expect(store.builtInDisabledByApp == false)
    #expect(backend.restoreCalls == 0)
}

@Test func disconnectAfterDisableRestoresBuiltInUsingLastKnownDisplay() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        builtInDisabledByApp: false,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "disable first")
    scheduler.advance(by: 0.5)
    #expect(store.builtInDisabledByApp == true)
    #expect(backend.disableCalls == 1)

    provider.snapshot = DisplaySnapshot(displays: [])
    controller.requestEvaluation(reason: "disconnect all externals")
    scheduler.advance(by: 0.5)

    #expect(store.builtInDisabledByApp == false)
    #expect(backend.restoreCalls == 1)
}

@Test func restoreWatchdogRecoversWhenDisconnectEventDoesNotArrive() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        builtInDisabledByApp: false,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 2.0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "disable first")
    scheduler.advance(by: 0.5)
    #expect(store.builtInDisabledByApp == true)
    #expect(backend.disableCalls == 1)

    provider.snapshot = DisplaySnapshot(displays: [])
    scheduler.advance(by: 2.0)

    #expect(store.builtInDisabledByApp == false)
    #expect(backend.restoreCalls == 1)
}

@Test func restoreWatchdogIgnoresPhantomExternalThatIsMissingFromIORegistry() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        builtInDisabledByApp: false,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 2.0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "disable first")
    scheduler.advance(by: 0.5)
    #expect(store.builtInDisabledByApp == true)

    provider.snapshot = DisplaySnapshot(displays: [
        .external(identity: identity, isDetectedInIORegistry: false)
    ])
    scheduler.advance(by: 2.0)

    #expect(store.builtInDisabledByApp == false)
    #expect(backend.restoreCalls == 1)
}

@Test func manualModeStillRestoresAppDisabledBuiltInWhenNoExternalIsConnected() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .manual,
        builtInDisabledByApp: false,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.manualDisableBuiltIn()
    #expect(store.builtInDisabledByApp == true)

    provider.snapshot = DisplaySnapshot(displays: [])
    controller.requestEvaluation(reason: "disconnect in manual mode")
    scheduler.advance(by: 0.5)

    #expect(store.builtInDisabledByApp == false)
    #expect(backend.restoreCalls == 1)
}

@Test func restoredBuiltInClearsAppDisabledStateWithoutRestoreAttempt() {
    let scheduler = TestScheduler()
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        builtInDisabledByApp: true,
        monitorRules: [:]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn()]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "built-in returned")
    scheduler.advance(by: 0.5)

    #expect(store.builtInDisabledByApp == false)
    #expect(backend.restoreCalls == 0)
}

@Test func prepareForTerminationRestoresUsingLastKnownBuiltInDisplay() {
    let scheduler = TestScheduler()
    let identity = MonitorIdentity.sample(name: "Home")
    let backend = FakeBackend()
    let store = InMemorySettingsStore(
        appMode: .auto,
        builtInDisabledByApp: false,
        monitorRules: [identity: MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")]
    )
    let provider = FakeSnapshotProvider(snapshot: DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)]))
    let controller = DisplayController(
        snapshotProvider: provider,
        policy: DisplayPolicy(),
        backend: backend,
        settingsStore: store,
        logger: EventLogger(),
        scheduler: scheduler,
        timing: DisplayControllerTiming(
            evaluationDebounceInterval: 0.5,
            topologySettleInterval: 0,
            failureRetryInterval: 10
        )
    )

    controller.requestEvaluation(reason: "disable first")
    scheduler.advance(by: 0.5)
    #expect(store.builtInDisabledByApp == true)

    provider.snapshot = DisplaySnapshot(displays: [.external(identity: identity)])
    controller.prepareForTermination()

    #expect(backend.restoreCalls == 1)
    #expect(store.builtInDisabledByApp == false)
}
