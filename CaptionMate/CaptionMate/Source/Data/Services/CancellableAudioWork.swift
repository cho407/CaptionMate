enum CancellableAudioWork {
    static func run<T: Sendable>(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let worker = Task.detached(priority: priority) {
            try Task.checkCancellation()
            let value = try operation()
            try Task.checkCancellation()
            return value
        }

        return try await withTaskCancellationHandler {
            // A synchronous decoder must finish before its worker can be released.
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }
}
