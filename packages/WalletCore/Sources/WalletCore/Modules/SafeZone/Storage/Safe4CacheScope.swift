import Foundation

/// A cache belongs to the network and owner that initiated the request.
/// Never derive this identity from the active network when an async request completes.
struct Safe4CacheScope: Hashable {
    let chainId: Int
    let owner: String

    init(chainId: Int, owner: String = "public") {
        self.chainId = chainId
        self.owner = owner.lowercased()
    }

    func key(_ name: String) -> String {
        "safe4_v2_\(chainId)_\(owner)_\(name)"
    }

    var databaseName: String {
        // Encode rather than interpolate an owner into a filesystem path.
        let encodedOwner = owner.utf8.map { String(format: "%02x", $0) }.joined()
        return "safe4-v2-\(chainId)-\(encodedOwner).sqlite"
    }
}
