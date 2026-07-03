import CoreGraphics
import Foundation
import LidopenCore

extension MonitorIdentity {
    static func sample(
        vendorID: UInt32 = 1,
        productID: UInt32 = 1,
        serialNumber: UInt32? = 1,
        name: String
    ) -> MonitorIdentity {
        MonitorIdentity(vendorID: vendorID, productID: productID, serialNumber: serialNumber, fallbackName: name)
    }
}

extension DisplayInfo {
    static func builtIn(displayID: CGDirectDisplayID = 1) -> DisplayInfo {
        DisplayInfo(
            displayID: displayID,
            name: "Built-in",
            isBuiltIn: true,
            isDetectedInIORegistry: true,
            isOnline: true,
            isActive: true,
            isAsleep: false,
            isMain: true,
            isInMirrorSet: false,
            bounds: .zero,
            modeDescription: nil,
            monitorIdentity: nil
        )
    }

    static func external(
        identity: MonitorIdentity,
        displayID: CGDirectDisplayID = 2,
        isDetectedInIORegistry: Bool = true
    ) -> DisplayInfo {
        DisplayInfo(
            displayID: displayID,
            name: identity.displayName,
            isBuiltIn: false,
            isDetectedInIORegistry: isDetectedInIORegistry,
            isOnline: true,
            isActive: true,
            isAsleep: false,
            isMain: false,
            isInMirrorSet: false,
            bounds: .zero,
            modeDescription: nil,
            monitorIdentity: identity
        )
    }
}

final class FakeSnapshotProvider: DisplaySnapshotProviding, @unchecked Sendable {
    var snapshot: DisplaySnapshot

    init(snapshot: DisplaySnapshot) {
        self.snapshot = snapshot
    }

    func captureSnapshot() -> DisplaySnapshot {
        snapshot
    }
}

final class FakeBackend: DisplayControlBackend, @unchecked Sendable {
    private(set) var disableCalls = 0
    private(set) var restoreCalls = 0
    private let failDisable: Bool
    private let failRestore: Bool

    init(failDisable: Bool = false, failRestore: Bool = false) {
        self.failDisable = failDisable
        self.failRestore = failRestore
    }

    func capabilities(for snapshot: DisplaySnapshot) -> DisplayControlCapabilities {
        DisplayControlCapabilities(backendName: "Fake", isAvailable: true, canDisableBuiltIn: true)
    }

    func disableBuiltIn(in snapshot: DisplaySnapshot) throws {
        disableCalls += 1
        if failDisable {
            throw DisplayControlError.operationFailed("disable failed")
        }
    }

    func restoreBuiltIn(in snapshot: DisplaySnapshot) throws {
        restoreCalls += 1
        if failRestore {
            throw DisplayControlError.operationFailed("restore failed")
        }
    }
}

final class TestScheduler: Scheduling, @unchecked Sendable {
    private struct Task {
        let date: Date
        let action: @Sendable () -> Void
        let token: TestToken
    }

    private final class TestToken: ScheduledTask, @unchecked Sendable {
        var isCancelled = false
        func cancel() {
            isCancelled = true
        }
    }

    private(set) var now: Date = Date(timeIntervalSince1970: 0)
    private var tasks: [Task] = []

    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> ScheduledTask {
        let token = TestToken()
        tasks.append(Task(date: now.addingTimeInterval(interval), action: action, token: token))
        return token
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
        let ready = tasks.filter { $0.date <= now && !$0.token.isCancelled }
        tasks.removeAll { $0.date <= now }
        ready.sorted { $0.date < $1.date }.forEach { $0.action() }
    }
}

final class FakeCGSLoader: CGSSymbolLoading, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var enabledValue: UInt32?

        func set(_ value: UInt32?) {
            lock.lock()
            defer { lock.unlock() }
            enabledValue = value
        }

        func get() -> UInt32? {
            lock.lock()
            defer { lock.unlock() }
            return enabledValue
        }
    }

    private static let state = State()

    static let configureDisplayEnabled: @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, UInt32) -> CGError = { _, _, value in
        state.set(value)
        return .success
    }

    let symbols: [String: UnsafeMutableRawPointer]
    let loaded: Bool

    init(symbols: [String: UnsafeMutableRawPointer], loaded: Bool) {
        self.symbols = symbols
        self.loaded = loaded
    }

    func loadSymbol<T>(named: String, as type: T.Type) -> T? {
        guard let symbol = symbols[named] else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    func isLoaded() -> Bool {
        loaded
    }

    static func reset() {
        state.set(nil)
    }

    static func recordedEnabledValue() -> UInt32? {
        state.get()
    }

    static func makeSymbol<T>(_ function: T) -> UnsafeMutableRawPointer {
        unsafeBitCast(function, to: UnsafeMutableRawPointer.self)
    }
}
