import Foundation

protocol ChildWalletActiveStateStore: AnyObject {
    func activeChildWalletId(parentAccountId: String) -> String?
    func setActiveChildWalletId(_ childWalletId: String?, parentAccountId: String)
    func delete(parentAccountId: String)
}

final class ChildWalletUserDefaultsActiveStateStore: ChildWalletActiveStateStore {
    private let userDefaults: UserDefaults
    private let key = "child-wallet.active-child-wallet-ids"
    private let lock = NSLock()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func activeChildWalletId(parentAccountId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        return activeChildWalletIds()[parentAccountId]
    }

    func setActiveChildWalletId(_ childWalletId: String?, parentAccountId: String) {
        lock.lock()
        defer { lock.unlock() }

        var activeChildWalletIds = activeChildWalletIds()
        if let childWalletId {
            activeChildWalletIds[parentAccountId] = childWalletId
        } else {
            activeChildWalletIds.removeValue(forKey: parentAccountId)
        }
        userDefaults.set(activeChildWalletIds, forKey: key)
    }

    func delete(parentAccountId: String) {
        setActiveChildWalletId(nil, parentAccountId: parentAccountId)
    }

    private func activeChildWalletIds() -> [String: String] {
        userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}

final class ChildWalletInMemoryActiveStateStore: ChildWalletActiveStateStore {
    private var activeChildWalletIds = [String: String]()
    private let lock = NSLock()

    func activeChildWalletId(parentAccountId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        return activeChildWalletIds[parentAccountId]
    }

    func setActiveChildWalletId(_ childWalletId: String?, parentAccountId: String) {
        lock.lock()
        defer { lock.unlock() }

        if let childWalletId {
            activeChildWalletIds[parentAccountId] = childWalletId
        } else {
            activeChildWalletIds.removeValue(forKey: parentAccountId)
        }
    }

    func delete(parentAccountId: String) {
        setActiveChildWalletId(nil, parentAccountId: parentAccountId)
    }
}
