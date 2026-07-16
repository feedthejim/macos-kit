import Foundation

func withAsyncTimeout<Value: Sendable>(
    seconds: Int,
    timeoutError: MacKitError,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
        let gate = AsyncTimeoutGate<Value>(continuation: continuation)
        gate.scheduleTimeout(seconds: seconds, error: timeoutError)

        Task {
            do {
                gate.resume(returning: try await operation())
            } catch {
                gate.resume(throwing: error)
            }
        }
    }
}

private final class AsyncTimeoutGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func scheduleTimeout(seconds: Int, error: MacKitError) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.resume(throwing: error)
        }
        lock.withLock {
            timeoutWorkItem = workItem
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .seconds(seconds),
            execute: workItem
        )
    }

    func resume(returning value: sending Value) {
        let continuation = takeContinuation()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        let continuation = takeContinuation()
        continuation?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.withLock {
            guard let continuation else { return nil }
            self.continuation = nil
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            return continuation
        }
    }
}
