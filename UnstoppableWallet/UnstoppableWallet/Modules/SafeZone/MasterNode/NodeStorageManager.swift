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
    private let recordId: Int64
    private let defaultPageControl: Safe4PageControl
    private var nodeInfoStorage = Core.shared.safe4StorageManager.safe4NodeInfoStorage
    private(set) var dataArray: [Safe4NodeInfo] = []
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let cacheNodePagekey: String
    private let cacheNodeTimestampKey: String
    private(set) var totalCacheNum: Int = 0
    private(set) var pageControl: Safe4PageControl? = nil

    init(nodeType: NodeStorageType, pageControl: Safe4PageControl, scopeKey: String? = nil) {
        self.nodeType = nodeType
        self.defaultPageControl = pageControl
        let normalizedScopeKey = scopeKey?.lowercased()
        let cacheKeySuffix = normalizedScopeKey.map { "_\($0)" } ?? ""
        self.recordId = Self.scopedRecordId(base: nodeType.cacheId, scopeKey: normalizedScopeKey)
        self.cacheNodePagekey = "safe4Node_page_\(nodeType.cacheId)\(cacheKeySuffix)_key"
        self.cacheNodeTimestampKey = "safe4Node_timestamp_\(nodeType.cacheId)\(cacheKeySuffix)_key"
        super.init()
        if let pageControl = getPageControl() {
            self.pageControl = pageControl
        }
        totalCacheNum = nodeInfoStorage.totalCount(forRecordId: recordId)
    }
    
    func load() -> [Safe4NodeInfo]? {
        if let infos = nodeInfoStorage.fetchAllNodeInfos(recordId: recordId), !infos.isEmpty {
            print("[NodeCache] load hit db recordId=\(recordId) count=\(infos.count) pageKey=\(cacheNodePagekey)")
            return sortedInfos(infos)
        }
        print("[NodeCache] load miss db recordId=\(recordId) pageKey=\(cacheNodePagekey)")
        return nil
    }
    
    func clearCaches() {
        savePageControl(defaultPageControl)
        nodeInfoStorage.deleteAllNodeInfos(recordId: recordId)
        userDefaultsStorage.set(value: nil as String?, for: cacheNodeTimestampKey)
        totalCacheNum = 0
        print("[NodeCache] clear recordId=\(recordId) pageKey=\(cacheNodePagekey)")
    }
    
    func save(pageControl: Safe4PageControl, infos: [Safe4NodeInfo]) {
        let storedCount = nodeInfoStorage.save(recordId: recordId, infos: infos)
        totalCacheNum = storedCount

        guard infos.isEmpty || storedCount == infos.count else {
            userDefaultsStorage.set(value: nil as TimeInterval?, for: cacheNodeTimestampKey)
            print("[NodeCache] save mismatch recordId=\(recordId) expected=\(infos.count) stored=\(storedCount) page=\(pageControl.page) total=\(pageControl.totalNum)")
            return
        }

        savePageControl(pageControl)
        userDefaultsStorage.set(value: Date().timeIntervalSince1970, for: cacheNodeTimestampKey)
        print("[NodeCache] save recordId=\(recordId) count=\(infos.count) storedCount=\(storedCount) page=\(pageControl.page) total=\(pageControl.totalNum)")
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

    private func sortedInfos(_ infos: [Safe4NodeInfo]) -> [Safe4NodeInfo] {
        var infos = infos
        switch nodeType {
        case .masterNode:
            infos.sort { Int($0.id)! > Int($1.id)! }
        case .superNode:
            if infos.contains(where: { $0.displayOrder != nil }) {
                infos = infos
                    .enumerated()
                    .sorted { lhs, rhs in
                        let lhsOrder = lhs.element.displayOrder ?? .max
                        let rhsOrder = rhs.element.displayOrder ?? .max
                        if lhsOrder == rhsOrder {
                            return lhs.offset < rhs.offset
                        }
                        return lhsOrder < rhsOrder
                    }
                    .map(\.element)
            } else {
                infos.sort { Int($0.id)! > Int($1.id)! }
            }
        }
        return infos
    }

    private static func scopedRecordId(base: Int64, scopeKey: String?) -> Int64 {
        guard let scopeKey, !scopeKey.isEmpty else {
            return base
        }

        let basePart = UInt64(base) << 48
        let scopePart = stableHash(scopeKey) & 0x0000_FFFF_FFFF_FFFF
        return Int64(bitPattern: basePart | scopePart)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}
