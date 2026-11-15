import Foundation

// Requests and invalidation belong to the main queue; expensive work is serialized
// in the background. Only the latest request may publish its result.
final class ManageWalletsTokenLoader<Value> {
    private let queue: DispatchQueue
    private var revision = 0
    private var pendingWork: DispatchWorkItem?

    init(queue: DispatchQueue = DispatchQueue(label: "manage-wallets.token-loader", qos: .userInitiated)) {
        self.queue = queue
    }

    deinit {
        pendingWork?.cancel()
    }

    func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        revision += 1
        pendingWork?.cancel()
        pendingWork = nil
    }

    func load(work: @escaping () -> Value, completion: @escaping (Value) -> Void) {
        invalidate()
        let revision = revision
        let workItem = DispatchWorkItem { [weak self] in
            let value = work()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == revision else {
                    return
                }
                self.pendingWork = nil
                completion(value)
            }
        }
        pendingWork = workItem
        queue.async(execute: workItem)
    }
}
