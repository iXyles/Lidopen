import Foundation

public protocol SettingsStore: AnyObject, Sendable {
    var appMode: AppMode { get set }
    var launchAtLoginEnabled: Bool { get set }
    var debugLoggingEnabled: Bool { get set }
    var builtInDisabledByApp: Bool { get set }
    var monitorRules: [MonitorIdentity: MonitorRule] { get set }
}

public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private enum Key {
        static let appMode = "appMode"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let debugLoggingEnabled = "debugLoggingEnabled"
        static let builtInDisabledByApp = "builtInDisabledByApp"
        static let monitorRules = "monitorRules"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var appMode: AppMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.appMode),
                  let mode = AppMode(rawValue: rawValue) else {
                return .auto
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appMode)
        }
    }

    public var launchAtLoginEnabled: Bool {
        get { defaults.bool(forKey: Key.launchAtLoginEnabled) }
        set { defaults.set(newValue, forKey: Key.launchAtLoginEnabled) }
    }

    public var debugLoggingEnabled: Bool {
        get { defaults.bool(forKey: Key.debugLoggingEnabled) }
        set { defaults.set(newValue, forKey: Key.debugLoggingEnabled) }
    }

    public var builtInDisabledByApp: Bool {
        get { defaults.bool(forKey: Key.builtInDisabledByApp) }
        set { defaults.set(newValue, forKey: Key.builtInDisabledByApp) }
    }

    public var monitorRules: [MonitorIdentity: MonitorRule] {
        get {
            guard let data = defaults.data(forKey: Key.monitorRules),
                  let rules = try? decoder.decode([String: MonitorRule].self, from: data) else {
                return [:]
            }
            return Dictionary(uniqueKeysWithValues: rules.values.map { ($0.identity, $0) })
        }
        set {
            let value = Dictionary(uniqueKeysWithValues: newValue.values.map { ($0.identity.id, $0) })
            let data = try? encoder.encode(value)
            defaults.set(data, forKey: Key.monitorRules)
        }
    }
}

public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    public init(
        appMode: AppMode = .auto,
        launchAtLoginEnabled: Bool = false,
        debugLoggingEnabled: Bool = false,
        builtInDisabledByApp: Bool = false,
        monitorRules: [MonitorIdentity: MonitorRule] = [:]
    ) {
        self.appMode = appMode
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.debugLoggingEnabled = debugLoggingEnabled
        self.builtInDisabledByApp = builtInDisabledByApp
        self.monitorRules = monitorRules
    }

    public var appMode: AppMode
    public var launchAtLoginEnabled: Bool
    public var debugLoggingEnabled: Bool
    public var builtInDisabledByApp: Bool
    public var monitorRules: [MonitorIdentity: MonitorRule]
}
