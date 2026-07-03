import CoreGraphics
import Darwin
import Foundation

public protocol CGSSymbolLoading: Sendable {
    func loadSymbol<T>(named: String, as type: T.Type) -> T?
    func isLoaded() -> Bool
}

public final class DlopenCGSSymbolLoader: CGSSymbolLoading, @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer?

    public init(path: String = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreGraphics.framework/CoreGraphics") {
        handle = dlopen(path, RTLD_NOW)
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    public func loadSymbol<T>(named: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, named) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    public func isLoaded() -> Bool {
        handle != nil
    }
}

public struct CGSDisplayEnableBackend: DisplayControlBackend {
    private typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, UInt32) -> CGError

    private let loader: CGSSymbolLoading

    public init(loader: CGSSymbolLoading = DlopenCGSSymbolLoader()) {
        self.loader = loader
    }

    public func capabilities(for snapshot: DisplaySnapshot) -> DisplayControlCapabilities {
        let hasBuiltIn = snapshot.builtInDisplay != nil
        let configure: ConfigureDisplayEnabled? = loader.loadSymbol(named: "CGSConfigureDisplayEnabled", as: ConfigureDisplayEnabled.self)

        return DisplayControlCapabilities(
            backendName: "Built-in display toggle",
            isAvailable: loader.isLoaded() && configure != nil,
            canDisableBuiltIn: hasBuiltIn && loader.isLoaded() && configure != nil,
            diagnostics: [
                "CGS display toggle: frameworkLoaded=\(loader.isLoaded()), configureDisplayEnabledSymbol=\(configure != nil).",
            ]
        )
    }

    public func disableBuiltIn(in snapshot: DisplaySnapshot) throws {
        try configureBuiltInDisplay(enabled: false, snapshot: snapshot)
    }

    public func restoreBuiltIn(in snapshot: DisplaySnapshot) throws {
        try configureBuiltInDisplay(enabled: true, snapshot: snapshot)
    }

    private func configureBuiltInDisplay(enabled: Bool, snapshot: DisplaySnapshot) throws {
        guard let builtIn = snapshot.builtInDisplay else {
            throw DisplayControlError.missingBuiltInDisplay
        }

        guard let configure: ConfigureDisplayEnabled = loader.loadSymbol(named: "CGSConfigureDisplayEnabled", as: ConfigureDisplayEnabled.self) else {
            throw DisplayControlError.backendUnavailable("CGSConfigureDisplayEnabled is unavailable.")
        }

        // The private symbol is applied inside a normal CoreGraphics display-configuration transaction.
        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success, let config else {
            throw DisplayControlError.operationFailed("CGBeginDisplayConfiguration failed with status \(formattedStatus(beginResult)).")
        }

        let configureResult = configure(config, builtIn.displayID, enabled ? 1 : 0)
        guard configureResult == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayControlError.operationFailed("CGSConfigureDisplayEnabled failed with status \(formattedStatus(configureResult)).")
        }

        let commitResult = CGCompleteDisplayConfiguration(config, .forSession)
        guard commitResult == .success else {
            throw DisplayControlError.operationFailed("CGCompleteDisplayConfiguration failed with status \(formattedStatus(commitResult)).")
        }
    }

    private func formattedStatus(_ result: CGError) -> String {
        let raw = Int32(result.rawValue)
        let hex = String(UInt32(bitPattern: raw), radix: 16, uppercase: true)
        return "\(raw) (0x\(hex))"
    }
}
