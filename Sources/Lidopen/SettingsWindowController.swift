import AppKit
import LidopenCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appModel: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsView(appModel: appModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Lidopen"
        window.setContentSize(NSSize(width: 860, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct SettingsView: View {
    @ObservedObject var appModel: AppModel

    private var displays: [DisplayInfo] {
        (appModel.snapshot?.displays ?? []).sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                modeCard
                displaySection
                rulesSection
                diagnosticsSection
            }
            .padding(24)
        }
        .frame(minWidth: 820, minHeight: 660)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(red: 0.94, green: 0.96, blue: 0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lidopen")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Monitor-aware built-in display automation for macOS")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appModel.diagnosticsText, forType: .string)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                StatusPill(title: appModel.appMode.displayName, tint: appModel.appMode == .auto ? .blue : .gray)
                StatusPill(title: appModel.backendCapabilities.backendName, tint: appModel.backendCapabilities.isAvailable ? .green : .orange)
                if appModel.builtInDisabledByApp {
                    StatusPill(title: "Built-in disabled", tint: .green)
                } else {
                    StatusPill(title: "Built-in active", tint: .secondary)
                }
            }
        }
    }

    private var modeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Behavior")
                    .font(.headline)

                Picker("Mode", selection: Binding(
                    get: { appModel.appMode },
                    set: { appModel.setAppMode($0) }
                )) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 24) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { appModel.launchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    ))

                    Toggle("Debug logging", isOn: Binding(
                        get: { appModel.debugLoggingEnabled },
                        set: { appModel.setDebugLoggingEnabled($0) }
                    ))
                }

                HStack(spacing: 12) {
                    Button(appModel.primaryManualDisplayActionTitle) {
                        appModel.performPrimaryManualDisplayAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appModel.canPerformPrimaryManualDisplayAction)

                    if !appModel.builtInDisabledByApp && !appModel.hasActiveExternalDisplay {
                        Text("Connect an external display to enable manual built-in disable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Refresh Displays") {
                        appModel.refresh()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var displaySection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connected Displays")
                    .font(.headline)

                if displays.isEmpty {
                    Text("No displays detected.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(displays) { display in
                            DisplayCard(
                                display: display,
                                rule: display.monitorIdentity.flatMap { identity in
                                    appModel.rules.first(where: { $0.identity == identity })
                                },
                                isUnknown: display.monitorIdentity.map { identity in
                                    appModel.pendingUnknownMonitors.contains(identity)
                                } ?? false,
                                onSaveDisable: {
                                    if let identity = display.monitorIdentity {
                                        appModel.saveRule(for: identity, preference: .disableBuiltIn)
                                    }
                                },
                                onSaveKeep: {
                                    if let identity = display.monitorIdentity {
                                        appModel.saveRule(for: identity, preference: .keepBuiltIn)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var rulesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Saved Monitor Rules")
                    .font(.headline)

                if appModel.rules.isEmpty {
                    Text("No saved rules yet. Connect a monitor and choose how it should behave.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(appModel.rules) { rule in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.lastSeenName)
                                        .font(.body.weight(.medium))
                                    Text(rule.identity.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { rule.preference },
                                    set: { appModel.updateRule(rule, preference: $0) }
                                )) {
                                    ForEach(MonitorPreference.allCases, id: \.self) { preference in
                                        Text(preference.displayName).tag(preference)
                                    }
                                }
                                .frame(width: 220)
                                .labelsHidden()
                                Button("Delete") {
                                    appModel.deleteRule(rule)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Diagnostics")
                    .font(.headline)

                if let message = appModel.lastErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last backend error")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent log")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appModel.logEntries.suffix(40)) { entry in
                                Text("\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.message)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(entry.isError ? .red : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 180)
                    .padding(12)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .textSelection(.enabled)
                }
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
    }
}

private struct StatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct DisplayCard: View {
    let display: DisplayInfo
    let rule: MonitorRule?
    let isUnknown: Bool
    let onSaveDisable: () -> Void
    let onSaveKeep: () -> Void

    private var subtitle: String {
        var parts: [String] = []
        parts.append(display.isBuiltIn ? "Built-in" : "External")
        if display.isMain {
            parts.append("Main")
        }
        if let mode = display.modeDescription, !mode.isEmpty {
            parts.append(mode)
        }
        return parts.joined(separator: " • ")
    }

    private var ruleTitle: String {
        if display.isBuiltIn {
            return display.isActive ? "Currently active" : "Not active"
        }
        if let rule {
            return rule.preference.displayName
        }
        if isUnknown {
            return "Needs a rule"
        }
        return "No saved rule"
    }

    private var tint: Color {
        if display.isBuiltIn {
            return .indigo
        }
        if let rule {
            return rule.preference == .disableBuiltIn ? .blue : .orange
        }
        return .gray
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(display.name)
                        .font(.body.weight(.semibold))
                    if display.isMain {
                        StatusPill(title: "Main", tint: .secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ruleTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }

            Spacer()

            if !display.isBuiltIn && isUnknown {
                HStack(spacing: 8) {
                    Button("Disable Built-in") {
                        onSaveDisable()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Keep Active") {
                        onSaveKeep()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
