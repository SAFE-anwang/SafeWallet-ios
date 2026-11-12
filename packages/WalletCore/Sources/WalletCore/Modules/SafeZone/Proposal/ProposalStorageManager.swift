import Foundation
import SwiftUI
import Combine

class ProposalStorageManager: NSObject {
    private let proposalInfoStorage: ProposalInfoStorage?
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let cachedPageControlKey: String
    private let cacheTimestampKey: String

    private(set) var pageControl: Safe4PageControl? = nil
    private(set) var totalCacheNum: Int = 0
    init(scope: Safe4CacheScope) {
        proposalInfoStorage = try? Core.shared.safe4StorageManager.scoped(scope).proposalInfoStorage
        cachedPageControlKey = scope.key("proposal_page")
        cacheTimestampKey = scope.key("proposal_timestamp")
        super.init()
        if let pageControl = getPageControl() {
            self.pageControl = pageControl
        }
        totalCacheNum = proposalInfoStorage?.countAll() ?? 0
    }

    func loadCaches() -> [ProposalInfoRecord] {
        return proposalInfoStorage?.fetchAllRecords()?.reversed() ?? []
    }

    func clearCaches() {
        savePageControl(Safe4PageControl(pageSize: 20, isReverse: true))
        proposalInfoStorage?.deleteAll()
        userDefaultsStorage.set(value: nil as String?, for: cacheTimestampKey)
        totalCacheNum = 0
    }

    func save(infos: [ProposalInfoRecord]) {
        proposalInfoStorage?.save(records: infos)
        userDefaultsStorage.set(value: Date().timeIntervalSince1970, for: cacheTimestampKey)
        totalCacheNum = proposalInfoStorage?.countAll() ?? 0
    }

    func savePageControl(_ pageControl: Safe4PageControl) {
        if let pageControlJSON = try? JSONEncoder().encode(pageControl) {
            let pageString = String(data: pageControlJSON, encoding: .utf8)
            userDefaultsStorage.set(value: pageString, for: cachedPageControlKey)
        }
    }

    func getPageControl() -> Safe4PageControl? {
        guard let pageControlData: String = userDefaultsStorage.value(for: cachedPageControlKey) else{ return nil}
        guard let pageControl = try? JSONDecoder().decode(Safe4PageControl.self, from: Data(pageControlData.utf8)) else{ return nil}
        return pageControl
    }

    func isCacheExpired(maxAge: TimeInterval) -> Bool {
        guard let timestamp: TimeInterval = userDefaultsStorage.value(for: cacheTimestampKey) else {
            return true
        }
        return Date().timeIntervalSince1970 - timestamp > maxAge
    }

    private static func newProposalTipsKey(scope: Safe4CacheScope) -> String {
        scope.key("proposal_isShow_new")
    }

    private static func proposalPopupReminderKey() -> String {
        "safe4_proposal_popup_reminder_key_\(Core.shared.accountManager.activeAccount?.id ?? "")"
    }

    static func getNeedShowTips(scope: Safe4CacheScope = Safe4CacheScope(chainId: Safe4Network.currentChainId, owner: Core.shared.accountManager.activeAccount?.id ?? "")) -> Bool {
        guard let isNeed: Bool = Core.shared.userDefaultsStorage.value(for: newProposalTipsKey(scope: scope)) else { return true }
        return isNeed
    }

    static func saveNeedShowTips(_ isNeed: Bool, scope: Safe4CacheScope = Safe4CacheScope(chainId: Safe4Network.currentChainId, owner: Core.shared.accountManager.activeAccount?.id ?? "")) {
        Core.shared.userDefaultsStorage.set(value: isNeed, for: newProposalTipsKey(scope: scope))
    }

    static func shouldShowProposalPopupReminder() -> Bool {
        guard let shouldShow: Bool = Core.shared.userDefaultsStorage.value(for: proposalPopupReminderKey()) else { return true }
        return shouldShow
    }

    static func saveShouldShowProposalPopupReminder(_ shouldShow: Bool) {
        Core.shared.userDefaultsStorage.set(value: shouldShow, for: proposalPopupReminderKey())
    }
}
