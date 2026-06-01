import Foundation
import SwiftUI
import Combine

enum NodeStorageType {
    case masterNode
    case superNode
    
    var cacheId: Int64 {
        switch self {
        case .masterNode: 10001
        case .superNode: 10002
        }
    }
}

class NodeStorageManager: NSObject {
    private let nodeType: NodeStorageType
    private let defaultPageControl: Safe4PageControl
    private var nodeInfoStorage = Core.shared.safe4StorageManager.safe4NodeInfoStorage
    private(set) var dataArray: [Safe4NodeInfo] = []
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let cacheNodePagekey: String
    private let cacheNodeTimestampKey: String
    private(set) var totalCacheNum: Int = 0
    private(set) var pageControl: Safe4PageControl? = nil

    init(nodeType: NodeStorageType, pageControl: Safe4PageControl) {
        self.nodeType = nodeType
        self.defaultPageControl = pageControl
        self.cacheNodePagekey = "safe4Node_page_\(nodeType.cacheId)_key"
        self.cacheNodeTimestampKey = "safe4Node_timestamp_\(nodeType.cacheId)_key"
        super.init()
        if let pageControl = getPageControl() {
            self.pageControl = pageControl
        }
        totalCacheNum = nodeInfoStorage.totalCount(forRecordId: nodeType.cacheId)
    }
    
    func load() -> [Safe4NodeInfo]? {
        if var infos = nodeInfoStorage.fetchAllNodeInfos(recordId: nodeType.cacheId) {
            infos.sort{ Int($0.id)! > Int($1.id)! }
            return infos
        }else {
            return nil
        }
    }
    
    func clearCaches() {
        savePageControl(defaultPageControl)
        nodeInfoStorage.deleteAllNodeInfos(recordId: nodeType.cacheId)
        userDefaultsStorage.set(value: nil as String?, for: cacheNodeTimestampKey)
        totalCacheNum = 0
    }
    
    func save(pageControl: Safe4PageControl, infos: [Safe4NodeInfo]) {
        savePageControl(pageControl)
        nodeInfoStorage.save(recordId: nodeType.cacheId, infos: infos)
        userDefaultsStorage.set(value: Date().timeIntervalSince1970, for: cacheNodeTimestampKey)
        totalCacheNum = nodeInfoStorage.totalCount(forRecordId: nodeType.cacheId)
    }
    
    func savePageControl(_ pageControl: Safe4PageControl) {
        if let pageControlJSON = try? JSONEncoder().encode(pageControl) {
            let pageString = String(data: pageControlJSON, encoding: .utf8)
            userDefaultsStorage.set(value: pageString, for: cacheNodePagekey)
        }
    }
    
    func getPageControl() -> Safe4PageControl? {
        guard let pageControlData: String = userDefaultsStorage.value(for: cacheNodePagekey) else{ return nil}
        guard let pageControl = try? JSONDecoder().decode(Safe4PageControl.self, from: Data(pageControlData.utf8)) else{ return nil}
        return pageControl
    }

    func isCacheExpired(maxAge: TimeInterval) -> Bool {
        guard let timestamp: TimeInterval = userDefaultsStorage.value(for: cacheNodeTimestampKey) else {
            return true
        }
        return Date().timeIntervalSince1970 - timestamp > maxAge
    }
}
