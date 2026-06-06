import Foundation
import SwiftUI
import Combine

class ProposalStorageManager: NSObject {
    private var proposalInfoStorage = Core.shared.safe4StorageManager.proposalInfoStorage
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let cachedPageControlKey: String = "safe4_proposal_info_key"
    private let cacheTimestampKey: String = "safe4_proposal_info_timestamp_key"

    private(set) var pageControl: Safe4PageControl? = nil
    private(set) var totalCacheNum: Int = 0
    override init() {
        super.init()
        if let pageControl = getPageControl() {
            self.pageControl = pageControl
        }
        totalCacheNum = proposalInfoStorage.countAll() ?? 0
    }
    
    func loadCaches() -> [ProposalInfoRecord] {
        return proposalInfoStorage.fetchAllRecords()?.reversed() ?? []
    }
    
    func clearCaches() {
        savePageControl(Safe4PageControl(pageSize: 20, isReverse: true))
        proposalInfoStorage.deleteAll()
        userDefaultsStorage.set(value: nil as String?, for: cacheTimestampKey)
        totalCacheNum = 0
    }
    
    func save(infos: [ProposalInfoRecord]) {
        proposalInfoStorage.save(records: infos)
        userDefaultsStorage.set(value: Date().timeIntervalSince1970, for: cacheTimestampKey)
        totalCacheNum = proposalInfoStorage.countAll() ?? 0
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

    private static func newProposalTipsKey() -> String {
        "safe4_proposal_isShow_new_key_\(Core.shared.accountManager.activeAccount?.id ?? "")"
    }

    private static func proposalPopupReminderKey() -> String {
        "safe4_proposal_popup_reminder_key_\(Core.shared.accountManager.activeAccount?.id ?? "")"
    }
    
    static func getNeedShowTips() -> Bool {
        guard let isNeed: Bool = Core.shared.userDefaultsStorage.value(for: newProposalTipsKey()) else { return true }
        return isNeed
    }
    
    static func saveNeedShowTips(_ isNeed: Bool) {
        Core.shared.userDefaultsStorage.set(value: isNeed, for: newProposalTipsKey())
    }

    static func shouldShowProposalPopupReminder() -> Bool {
        guard let shouldShow: Bool = Core.shared.userDefaultsStorage.value(for: proposalPopupReminderKey()) else { return true }
        return shouldShow
    }

    static func saveShouldShowProposalPopupReminder(_ shouldShow: Bool) {
        Core.shared.userDefaultsStorage.set(value: shouldShow, for: proposalPopupReminderKey())
    }
}
