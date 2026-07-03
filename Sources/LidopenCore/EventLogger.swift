import Foundation

public final class EventLogger: @unchecked Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let date: Date
        public let message: String
        public let isError: Bool

        public init(date: Date, message: String, isError: Bool) {
            self.date = date
            self.message = message
            self.isError = isError
        }
    }

    private let maxEntries: Int
    private let lock = NSLock()
    private var entriesStorage: [Entry] = []

    public init(maxEntries: Int = 200) {
        self.maxEntries = max(1, maxEntries)
    }

    public func info(_ message: String) {
        append(message: message, isError: false)
    }

    public func error(_ message: String) {
        append(message: message, isError: true)
    }

    public func entries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entriesStorage
    }

    private func append(message: String, isError: Bool) {
        lock.lock()
        defer { lock.unlock() }
        entriesStorage.append(Entry(date: Date(), message: message, isError: isError))
        if entriesStorage.count > maxEntries {
            entriesStorage.removeFirst(entriesStorage.count - maxEntries)
        }
    }
}
