import CoreGraphics
import Foundation

public enum AppMode: String, Codable, CaseIterable, Sendable {
    case manual
    case auto

    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .auto: "Auto"
        }
    }
}

public enum MonitorPreference: String, Codable, CaseIterable, Sendable {
    case disableBuiltIn
    case keepBuiltIn

    public var displayName: String {
        switch self {
        case .disableBuiltIn: "Disable built-in"
        case .keepBuiltIn: "Keep built-in active"
        }
    }
}

public struct MonitorIdentity: Hashable, Codable, Identifiable, Sendable {
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32?
    public let fallbackName: String

    public init(vendorID: UInt32, productID: UInt32, serialNumber: UInt32?, fallbackName: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.fallbackName = fallbackName
    }

    public var id: String {
        "\(vendorID)-\(productID)-\(serialNumber.map(String.init) ?? "noserial")-\(fallbackName)"
    }

    public var displayName: String {
        if fallbackName.isEmpty {
            return "Monitor \(vendorID):\(productID)"
        }
        return fallbackName
    }
}

public struct MonitorRule: Codable, Identifiable, Hashable, Sendable {
    public let identity: MonitorIdentity
    public var preference: MonitorPreference
    public var lastSeenName: String

    public init(identity: MonitorIdentity, preference: MonitorPreference, lastSeenName: String) {
        self.identity = identity
        self.preference = preference
        self.lastSeenName = lastSeenName
    }

    public var id: String { identity.id }
}

public struct DisplayInfo: Identifiable, Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool
    public let isDetectedInIORegistry: Bool
    public let isOnline: Bool
    public let isActive: Bool
    public let isAsleep: Bool
    public let isMain: Bool
    public let isInMirrorSet: Bool
    public let bounds: CGRect
    public let modeDescription: String?
    public let monitorIdentity: MonitorIdentity?

    public init(
        displayID: CGDirectDisplayID,
        name: String,
        isBuiltIn: Bool,
        isDetectedInIORegistry: Bool,
        isOnline: Bool,
        isActive: Bool,
        isAsleep: Bool,
        isMain: Bool,
        isInMirrorSet: Bool,
        bounds: CGRect,
        modeDescription: String?,
        monitorIdentity: MonitorIdentity?
    ) {
        self.displayID = displayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isDetectedInIORegistry = isDetectedInIORegistry
        self.isOnline = isOnline
        self.isActive = isActive
        self.isAsleep = isAsleep
        self.isMain = isMain
        self.isInMirrorSet = isInMirrorSet
        self.bounds = bounds
        self.modeDescription = modeDescription
        self.monitorIdentity = monitorIdentity
    }

    public var id: UInt32 { displayID }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public let displays: [DisplayInfo]
    public let capturedAt: Date

    public init(displays: [DisplayInfo], capturedAt: Date = Date()) {
        self.displays = displays
        self.capturedAt = capturedAt
    }

    public var builtInDisplay: DisplayInfo? {
        displays.first(where: \.isBuiltIn)
    }

    public var externalDisplays: [DisplayInfo] {
        displays.filter { !$0.isBuiltIn }
    }

    public var activeExternalDisplays: [DisplayInfo] {
        externalDisplays.filter { $0.isOnline && $0.isActive && !$0.isAsleep }
    }

    public var physicallyConnectedExternalDisplays: [DisplayInfo] {
        activeExternalDisplays.filter(\.isDetectedInIORegistry)
    }

    public var hasBuiltInDisplay: Bool {
        builtInDisplay != nil
    }
}

public enum DisplayDecision: Equatable, Sendable {
    case noop(reason: String)
    case disableBuiltIn
    case restoreBuiltIn
    case promptForUnknownMonitor([MonitorIdentity])
}

public struct PolicyEvaluation: Equatable, Sendable {
    public let decision: DisplayDecision
    public let unknownMonitors: [MonitorIdentity]

    public init(decision: DisplayDecision, unknownMonitors: [MonitorIdentity]) {
        self.decision = decision
        self.unknownMonitors = unknownMonitors
    }
}

public struct DisplayControlCapabilities: Equatable, Sendable {
    public let backendName: String
    public let isAvailable: Bool
    public let canDisableBuiltIn: Bool
    public let diagnostics: [String]

    public init(backendName: String, isAvailable: Bool, canDisableBuiltIn: Bool, diagnostics: [String] = []) {
        self.backendName = backendName
        self.isAvailable = isAvailable
        self.canDisableBuiltIn = canDisableBuiltIn
        self.diagnostics = diagnostics
    }
}

public struct ControllerState: Equatable, Sendable {
    public let snapshot: DisplaySnapshot?
    public let pendingUnknownMonitors: [MonitorIdentity]
    public let lastDecision: DisplayDecision
    public let builtInDisabledByApp: Bool
    public let lastErrorMessage: String?
    public let capabilities: DisplayControlCapabilities

    public init(
        snapshot: DisplaySnapshot?,
        pendingUnknownMonitors: [MonitorIdentity],
        lastDecision: DisplayDecision,
        builtInDisabledByApp: Bool,
        lastErrorMessage: String?,
        capabilities: DisplayControlCapabilities
    ) {
        self.snapshot = snapshot
        self.pendingUnknownMonitors = pendingUnknownMonitors
        self.lastDecision = lastDecision
        self.builtInDisabledByApp = builtInDisabledByApp
        self.lastErrorMessage = lastErrorMessage
        self.capabilities = capabilities
    }
}
