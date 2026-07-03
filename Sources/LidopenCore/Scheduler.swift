import Foundation

public protocol ScheduledTask: AnyObject, Sendable {
    func cancel()
}

public protocol Scheduling: Sendable {
    var now: Date { get }
    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> ScheduledTask
}

public final class DispatchScheduledTask: ScheduledTask, @unchecked Sendable {
    private var workItem: DispatchWorkItem?

    public init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    public func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

public struct DispatchScheduler: Scheduling {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public var now: Date { Date() }

    public func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> ScheduledTask {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
        return DispatchScheduledTask(workItem: workItem)
    }
}
