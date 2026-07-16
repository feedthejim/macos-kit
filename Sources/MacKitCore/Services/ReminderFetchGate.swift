@preconcurrency import EventKit
import Foundation

/// Completes an EventKit reminder fetch exactly once, including when EventKit
/// never invokes its callback after a permission or daemon failure.
final class ReminderFetchGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let store: EKEventStore
    private var continuation: CheckedContinuation<Value, Error>?
    private var fetchRequest: Any?
    private var timeoutWorkItem: DispatchWorkItem?

    init(store: EKEventStore, continuation: CheckedContinuation<Value, Error>) {
        self.store = store
        self.continuation = continuation
    }

    func install(fetchRequest: Any, timeoutSeconds: Int) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            store.cancelFetchRequest(fetchRequest)
            return
        }

        self.fetchRequest = fetchRequest
        let workItem = DispatchWorkItem { [weak self] in
            self?.timeOut(timeoutSeconds: timeoutSeconds)
        }
        timeoutWorkItem = workItem
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .seconds(timeoutSeconds),
            execute: workItem
        )
    }

    func resume(returning value: sending Value) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        fetchRequest = nil
        lock.unlock()

        continuation.resume(returning: value)
    }

    private func timeOut(timeoutSeconds: Int) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let request = fetchRequest
        fetchRequest = nil
        timeoutWorkItem = nil
        lock.unlock()

        if let request {
            store.cancelFetchRequest(request)
        }
        continuation.resume(throwing: MacKitError.systemError(
            "Reminders did not respond within \(timeoutSeconds) seconds. "
            + "Check System Settings > Privacy & Security > Reminders and try again."
        ))
    }
}
