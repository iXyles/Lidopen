import Foundation

public protocol DisplayControlBackend: Sendable {
    func capabilities(for snapshot: DisplaySnapshot) -> DisplayControlCapabilities
    func disableBuiltIn(in snapshot: DisplaySnapshot) throws
    func restoreBuiltIn(in snapshot: DisplaySnapshot) throws
}

public enum DisplayControlError: LocalizedError, Equatable, Sendable {
    case missingBuiltInDisplay
    case backendUnavailable(String)
    case unsupported(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingBuiltInDisplay:
            return "No built-in display is available."
        case let .backendUnavailable(message),
             let .unsupported(message),
             let .operationFailed(message):
            return message
        }
    }
}

public struct NoOpDisplayControlBackend: DisplayControlBackend {
    public init() {}

    public func capabilities(for snapshot: DisplaySnapshot) -> DisplayControlCapabilities {
        DisplayControlCapabilities(
            backendName: "No-op backend",
            isAvailable: false,
            canDisableBuiltIn: false,
            diagnostics: ["No display control backend is configured."]
        )
    }

    public func disableBuiltIn(in snapshot: DisplaySnapshot) throws {
        throw DisplayControlError.backendUnavailable("No-op backend cannot disable the built-in display.")
    }

    public func restoreBuiltIn(in snapshot: DisplaySnapshot) throws {
        throw DisplayControlError.backendUnavailable("No-op backend cannot restore the built-in display.")
    }
}
