import Foundation
import LidopenCore

struct AppDiagnosticsSnapshot {
    let appMode: AppMode
    let builtInDisabledByApp: Bool
    let backendCapabilities: DisplayControlCapabilities
    let lastErrorMessage: String?
    let snapshot: DisplaySnapshot?
    let pendingUnknownMonitors: [MonitorIdentity]
    let rules: [MonitorRule]
    let logEntries: [EventLogger.Entry]
}

struct AppDiagnosticsFormatter {
    func format(_ snapshot: AppDiagnosticsSnapshot) -> String {
        var lines: [String] = []
        lines.append("Lidopen Diagnostics")
        lines.append("Mode: \(snapshot.appMode.displayName)")
        lines.append("Built-in disabled by app: \(snapshot.builtInDisabledByApp)")
        lines.append("Backend: \(snapshot.backendCapabilities.backendName)")
        lines.append("Backend available: \(snapshot.backendCapabilities.isAvailable)")
        lines.append("Backend can disable built-in: \(snapshot.backendCapabilities.canDisableBuiltIn)")

        if !snapshot.backendCapabilities.diagnostics.isEmpty {
            lines.append("Backend diagnostics:")
            for diagnostic in snapshot.backendCapabilities.diagnostics {
                lines.append("- \(diagnostic)")
            }
        }

        if let message = snapshot.lastErrorMessage, !message.isEmpty {
            lines.append("Last backend error: \(message)")
        }

        if let displaySnapshot = snapshot.snapshot {
            lines.append("Displays:")
            for display in displaySnapshot.displays {
                let identity = display.monitorIdentity?.id ?? "built-in"
                lines.append("- \(display.name) | id=\(display.displayID) | type=\(display.isBuiltIn ? "built-in" : "external") | ioRegistry=\(display.isDetectedInIORegistry) | online=\(display.isOnline) | active=\(display.isActive) | asleep=\(display.isAsleep) | main=\(display.isMain) | mirror=\(display.isInMirrorSet) | identity=\(identity)")
            }
        }

        if !snapshot.pendingUnknownMonitors.isEmpty {
            lines.append("Unknown monitors:")
            for monitor in snapshot.pendingUnknownMonitors {
                lines.append("- \(monitor.displayName) | \(monitor.id)")
            }
        }

        if !snapshot.rules.isEmpty {
            lines.append("Saved rules:")
            for rule in snapshot.rules {
                lines.append("- \(rule.lastSeenName) | \(rule.identity.id) | \(rule.preference.displayName)")
            }
        }

        if !snapshot.logEntries.isEmpty {
            lines.append("Recent log:")
            for entry in snapshot.logEntries {
                lines.append("\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.message)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
