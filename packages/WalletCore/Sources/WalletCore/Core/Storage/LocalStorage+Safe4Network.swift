import Foundation

extension LocalStorage {
    private var safe4TestNetKey: String { "safe4-test-net" }

    var isSafe4TestNet: Bool {
        get { userDefaultsStorage.value(for: safe4TestNetKey) ?? false }
        set { userDefaultsStorage.set(value: newValue, for: safe4TestNetKey) }
    }
}
