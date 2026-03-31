import Foundation
import SwiftUI
import Combine

class ProposalStorageManager: NSObject {
    private var proposalInfoStorage = Core.shared.safe4StorageManager.proposalInfoStorage
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let cachedPageControlKey: String = "safe4_proposal_info_key"

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
        totalCacheNum = 0
    }
    
    func save(infos: [ProposalInfoRecord]) {
        proposalInfoStorage.save(records: infos)
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
    
    static func getNeedShowTips() -> Bool {
        let isShowNewProposalKey: String = "safe4_proposal_isShow_new_key_\(Core.shared.accountManager.activeAccount?.id ?? "")"
        guard let isNeed: Bool = Core.shared.userDefaultsStorage.value(for: isShowNewProposalKey) else{ return true }
        return isNeed
    }
    
    static func saveNeedShowTips(_ isNeed: Bool) {
        let isShowNewProposalKey: String = "safe4_proposal_isShow_new_key_\(Core.shared.accountManager.activeAccount?.id ?? "")"
        Core.shared.userDefaultsStorage.set(value: isNeed, for: isShowNewProposalKey)
    }
}
