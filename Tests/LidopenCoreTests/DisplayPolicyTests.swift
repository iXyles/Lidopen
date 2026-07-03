import LidopenCore
import Testing

@Test func manualModeNeverAutoToggles() {
    let policy = DisplayPolicy()
    let rule = MonitorRule(identity: .sample(name: "Home"), preference: .disableBuiltIn, lastSeenName: "Home")
    let snapshot = DisplaySnapshot(displays: [.builtIn(), .external(identity: rule.identity)])

    let evaluation = policy.evaluate(snapshot: snapshot, appMode: .manual, rules: [rule.identity: rule])

    #expect(evaluation.decision == .noop(reason: "Manual mode"))
}

@Test func knownDisableMonitorDisablesBuiltIn() {
    let policy = DisplayPolicy()
    let identity = MonitorIdentity.sample(name: "Home")
    let rule = MonitorRule(identity: identity, preference: .disableBuiltIn, lastSeenName: "Home")
    let snapshot = DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)])

    let evaluation = policy.evaluate(snapshot: snapshot, appMode: .auto, rules: [identity: rule])

    #expect(evaluation.decision == .disableBuiltIn)
}

@Test func knownKeepMonitorKeepsBuiltInOn() {
    let policy = DisplayPolicy()
    let identity = MonitorIdentity.sample(name: "Projector")
    let rule = MonitorRule(identity: identity, preference: .keepBuiltIn, lastSeenName: "Projector")
    let snapshot = DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)])

    let evaluation = policy.evaluate(snapshot: snapshot, appMode: .auto, rules: [identity: rule])

    #expect(evaluation.decision == .noop(reason: "Known monitor prefers keeping built-in active"))
}

@Test func unknownMonitorPromptsForRule() {
    let policy = DisplayPolicy()
    let identity = MonitorIdentity.sample(name: "Unknown")
    let snapshot = DisplaySnapshot(displays: [.builtIn(), .external(identity: identity)])

    let evaluation = policy.evaluate(snapshot: snapshot, appMode: .auto, rules: [:])

    #expect(evaluation.decision == .promptForUnknownMonitor([identity]))
}

@Test func conflictingRulesPreferKeepBuiltIn() {
    let policy = DisplayPolicy()
    let home = MonitorIdentity.sample(name: "Home")
    let projector = MonitorIdentity.sample(vendorID: 2, productID: 2, serialNumber: 2, name: "Projector")
    let snapshot = DisplaySnapshot(displays: [.builtIn(), .external(identity: home), .external(identity: projector)])
    let rules = [
        home: MonitorRule(identity: home, preference: .disableBuiltIn, lastSeenName: "Home"),
        projector: MonitorRule(identity: projector, preference: .keepBuiltIn, lastSeenName: "Projector"),
    ]

    let evaluation = policy.evaluate(snapshot: snapshot, appMode: .auto, rules: rules)

    #expect(evaluation.decision == .noop(reason: "Conflicting monitor rules"))
}

@Test func noActiveExternalDisplaysDoesNotAskPolicyToRestore() {
    let policy = DisplayPolicy()
    let snapshot = DisplaySnapshot(displays: [.builtIn()])

    let evaluation = policy.evaluate(snapshot: snapshot, appMode: .auto, rules: [:])

    #expect(evaluation.decision == .noop(reason: "No active external displays"))
}
