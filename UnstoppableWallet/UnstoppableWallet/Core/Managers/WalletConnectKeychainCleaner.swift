import Foundation
import Security

enum WalletConnectKeychainCleaner {

    private static let reownKeychainService = "com.walletconnect.sdk"
    private static let bundleIdKey = "wc_bundle_identifier"
    static let fixedAppGroupId = "group.com.anwang4.safewallet"

    static func clearIfNeeded(currentBundleId: String) -> Bool {
        let storedBundleId = UserDefaults.standard.string(forKey: bundleIdKey)

        if let stored = storedBundleId, stored == currentBundleId {
            return false
        }

        clearReownLocalData()
        UserDefaults.standard.set(currentBundleId, forKey: bundleIdKey)
        return true
    }

    static func forceClearAndReset(currentBundleId: String) {
        clearReownLocalData()
        UserDefaults.standard.set(currentBundleId, forKey: bundleIdKey)
    }

    static func handleKeychainErrorIfNeeded(_ error: Error) -> Bool {
        let errorString = String(reflecting: error)

        if errorString.contains("-34018") ||
           errorString.contains("errSecMissingEntitlement") ||
           errorString.contains("errSecNoDefaultKeychain") {

            forceClearAndReset(currentBundleId: Bundle.main.bundleIdentifier ?? "")
            return true
        }

        return false
    }

    static var diagnosticInfo: [String: String] {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let groupId = fixedAppGroupId
        let storedBundleId = UserDefaults.standard.string(forKey: bundleIdKey) ?? "nil"

        var keychainStatus = "unknown"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reownKeychainService,
            kSecAttrAccessGroup as String: groupId,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        switch status {
        case errSecSuccess:
            if let results = items as? [[String: Any]] {
                keychainStatus = "\(results.count) items found"
            } else {
                keychainStatus = "success but no items"
            }
        case errSecItemNotFound:
            keychainStatus = "empty (no items)"
        case -34018:
            keychainStatus = "ERROR: -34018 (entitlement mismatch)"
        default:
            keychainStatus = "error: \(status)"
        }

        return [
            "current_bundle_id": bundleId,
            "stored_bundle_id": storedBundleId,
            "group_id": groupId,
            "bundle_id_changed": storedBundleId != bundleId ? "YES" : "NO",
            "keychain_status": keychainStatus
        ]
    }

    private static func clearReownLocalData() {
        clearReownKeychainItemsByService()
        clearNotifyGroupKeychainItems()
        clearReownUserDefaults()
        clearReownFileSystemData()
    }

    private static func clearReownKeychainItemsByService() {
        let currentGroupId = fixedAppGroupId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reownKeychainService,
            kSecAttrAccessGroup as String: currentGroupId,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        if status == errSecSuccess, let results = items as? [[String: Any]] {
            for item in results {
                guard let acct = item[kSecAttrAccount as String] as? String else { continue }

                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: reownKeychainService,
                    kSecAttrAccount as String: acct,
                    kSecAttrAccessGroup as String: currentGroupId
                ]

                SecItemDelete(deleteQuery as CFDictionary)
            }
        }
    }

    private static func clearNotifyGroupKeychainItems() {
        let currentGroupId = fixedAppGroupId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: currentGroupId,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        if status == errSecSuccess, let results = items as? [[String: Any]] {
            for item in results {
                guard let acct = item[kSecAttrAccount as String] as? String else { continue }

                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: currentGroupId,
                    kSecAttrAccount as String: acct
                ]

                SecItemDelete(deleteQuery as CFDictionary)
            }
        }
    }

    private static func clearReownUserDefaults() {
        let groupId = fixedAppGroupId

        guard let groupDefaults = UserDefaults(suiteName: groupId) else { return }
        let domain = groupDefaults.dictionaryRepresentation()

        for key in domain.keys {
            groupDefaults.removeObject(forKey: key)
        }
        groupDefaults.synchronize()
    }

    private static func clearReownFileSystemData() {
        let fileManager = FileManager.default

        let directories: [FileManager.SearchPathDirectory] = [
            .applicationSupportDirectory,
            .cachesDirectory,
            .documentDirectory
        ]

        for directory in directories {
            guard let url = try? fileManager.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: false) else { continue }

            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }

            for item in contents {
                let itemName = item.lastPathComponent.lowercased()
                let itemPath = item.path.lowercased()

                if itemName.contains("walletconnect") || itemName.contains("reown") ||
                   itemPath.contains("walletconnect") || itemPath.contains("reown") ||
                   itemName.contains("iridium") || itemPath.contains("iridium") {
                    try? fileManager.removeItem(at: item)
                }
            }
        }
    }
}
