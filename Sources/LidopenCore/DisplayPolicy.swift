import Foundation

public struct DisplayPolicy: Sendable {
    public init() {}

    public func evaluate(
        snapshot: DisplaySnapshot,
        appMode: AppMode,
        rules: [MonitorIdentity: MonitorRule]
    ) -> PolicyEvaluation {
        let unknownMonitors = snapshot.activeExternalDisplays.compactMap(\.monitorIdentity)
            .filter { rules[$0] == nil }

        guard snapshot.hasBuiltInDisplay else {
            return PolicyEvaluation(
                decision: .noop(reason: "No built-in display present"),
                unknownMonitors: unknownMonitors
            )
        }

        guard appMode == .auto else {
            return PolicyEvaluation(
                decision: .noop(reason: "Manual mode"),
                unknownMonitors: unknownMonitors
            )
        }

        let activeExternals = snapshot.activeExternalDisplays
        guard !activeExternals.isEmpty else {
            return PolicyEvaluation(
                decision: .noop(reason: "No active external displays"),
                unknownMonitors: []
            )
        }

        let preferences = activeExternals.compactMap { display -> MonitorPreference? in
            guard let identity = display.monitorIdentity else { return nil }
            return rules[identity]?.preference
        }

        let hasDisable = preferences.contains(.disableBuiltIn)
        let hasKeep = preferences.contains(.keepBuiltIn)

        if hasKeep {
            return PolicyEvaluation(
                decision: .noop(reason: hasDisable ? "Conflicting monitor rules" : "Known monitor prefers keeping built-in active"),
                unknownMonitors: unknownMonitors
            )
        }

        if hasDisable {
            return PolicyEvaluation(
                decision: .disableBuiltIn,
                unknownMonitors: unknownMonitors
            )
        }

        if !unknownMonitors.isEmpty {
            return PolicyEvaluation(
                decision: .promptForUnknownMonitor(unknownMonitors),
                unknownMonitors: unknownMonitors
            )
        }

        return PolicyEvaluation(
            decision: .noop(reason: "No monitor rule requires changes"),
            unknownMonitors: []
        )
    }
}
