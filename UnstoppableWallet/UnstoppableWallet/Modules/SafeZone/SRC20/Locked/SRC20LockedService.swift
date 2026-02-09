import Foundation
import Combine
import web3swift
import Web3Core
import BigInt
import EvmKit
import HsExtensions

class SRC20LockedService {
    private(set) var state: SRC20LockedService.State
    private let pageSize = 20
    private let idsConcurrencyLimit = 4
    private let recordsConcurrencyLimit = 8
    private lazy var pageControl = Safe4PageControl(pageSize: pageSize)
    private let service: SRC20Service
    private let lockedRecordStorage: Src20AllTokenLockedRecordStorage
    private var lockedAmountSubject = PassthroughSubject<BigUInt, Never>()
    private var tasks = Set<AnyTask>()
    init(service: SRC20Service, lockedRecordStorage: Src20AllTokenLockedRecordStorage) {
        self.service = service
        self.lockedRecordStorage = lockedRecordStorage
        state = .notSynced(error: AppError.unknownError.localizedDescription)
        sync()
    }
    
    func start() {
        if .syncing != state {
            sync()
        }
    }

    var lockedAmountPublisher: AnyPublisher<BigUInt, Never> {
        lockedAmountSubject.eraseToAnyPublisher()
    }
    
    private func sync() {
        Task { [weak self] in
            do {
                guard let self = self else { return }
                state = .syncing
                let cachedRecords = (try? lockedRecordStorage.tokenRecords(tokenContract: service.contract)) ?? []
                let totalNum = try await service.getLockedIDNum()
                if totalNum == 0 {
                    if !cachedRecords.isEmpty {
                        lockedRecordStorage.delete(tokenContract: service.contract)
                    }
                    lockedAmountSubject.send(.zero)
                    state = .synced
                    return
                }
                pageControl.set(totalNum: Int(totalNum))
                let allIds = try await requestAllIds(totalNum: Int(totalNum))
                let records = try await requestRecords(ids: allIds)
                if records.isEmpty {
                    let totalAmount = totalAmount(from: records)
                    lockedAmountSubject.send(totalAmount)
                    state = .synced
                    return
                }
                updateCache(records: records, cachedRecords: cachedRecords)
                let totalAmount = totalAmount(from: records)
                lockedAmountSubject.send(totalAmount)
                state = .synced
            }catch {
                self?.state = .notSynced(error: "Service Error")
            }
        }.store(in: &tasks)
    }
    
    private func requestAllIds(totalNum: Int) async throws -> [BigUInt] {
        var idPageControl = Safe4PageControl(pageSize: pageSize)
        idPageControl.set(totalNum: totalNum)
        let pageParams = idPageControl.pageArray.compactMap { page -> (start: Int, count: Int)? in
            guard let start = page.first else { return nil }
            return (start: start, count: page.count)
        }
        let idPages = try await collectWithLimit(items: pageParams, limit: idsConcurrencyLimit) { [service] params in
            try await service.getLockedIDs(start: BigUInt(params.start), count: BigUInt(params.count))
        }
        return idPages.flatMap { $0 }
    }
    
    private func requestRecords(ids: [BigUInt]) async throws -> [LockRecord] {
        try await collectWithLimit(items: ids, limit: recordsConcurrencyLimit) { [service] id in
            try await service.getRecordByID(id: id)
        }
    }
    
    private func collectWithLimit<T, R>(items: [T], limit: Int, operation: @escaping (T) async throws -> R) async throws -> [R] {
        let safeLimit = max(1, limit)
        var results: [R] = []
        
        try await withThrowingTaskGroup(of: R.self) { group in
            var index = 0
            var inFlight = 0
            
            while index < items.count {
                if inFlight >= safeLimit {
                    if let value = try await group.next() {
                        results.append(value)
                        inFlight -= 1
                    }
                    continue
                }
                
                let item = items[index]
                index += 1
                inFlight += 1
                group.addTask {
                    try await operation(item)
                }
            }
            
            while inFlight > 0 {
                if let value = try await group.next() {
                    results.append(value)
                    inFlight -= 1
                }
            }
        }
        
        return results
    }

    private func updateCache(records: [LockRecord], cachedRecords: [Src20TokenLockedRecord]) {
        let newKeys = Set(records.map { recordKey(id: Int($0.id), addr: $0.addr.address) })
        let cachedKeys = Set(cachedRecords.map { RecordKey(id: $0.id, addr: $0.addr.lowercased()) })

        let expiredKeys = cachedKeys.subtracting(newKeys)
        for key in expiredKeys {
            lockedRecordStorage.delete(id: key.id, addr: key.addr)
        }

        let newRecords = records.map { Src20TokenLockedRecord(info: $0, tokenContract: service.contract) }
        lockedRecordStorage.save(recoards: newRecords)
    }

    private func recordKey(id: Int, addr: String) -> RecordKey {
        RecordKey(id: id, addr: addr.lowercased())
    }

    private func totalAmount(from records: [LockRecord]) -> BigUInt {
        records.map{$0.amount}.reduce(0,+)
    }

    private func totalAmount(from records: [Src20TokenLockedRecord]) -> BigUInt {
        records.map{BigUInt($0.amount)!}.reduce(0,+)
    }
}

extension SRC20LockedService {
    struct RecordKey: Hashable {
        let id: Int
        let addr: String
    }

    enum State: Hashable {
        case synced
        case syncing
        case notSynced(error: String)

        var isSynced: Bool {
            switch self {
            case .synced: return true
            default: return false
            }
        }

        var isNotSynced: Bool {
            switch self {
            case .notSynced: return true
            default: return false
            }
        }

        var syncing: Bool {
            switch self {
            case .syncing: return true
            default: return false
            }
        }
    }

}
