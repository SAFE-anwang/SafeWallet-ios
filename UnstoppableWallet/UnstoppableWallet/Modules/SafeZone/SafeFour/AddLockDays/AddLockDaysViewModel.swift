import Foundation
import BigInt
import RxSwift
import RxRelay
import Web3Core
import web3swift

class AddLockDaysViewModel {
    private let service: AddLockDaysService
    private let type: LockNodeType
    
    private let stateRelay = PublishRelay<State>()
    
    private var ids = [BigUInt]()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init(service: AddLockDaysService, type: LockNodeType) {
        self.service = service
        self.type = type
        
        switch type {
        case let .masterNode(info):
            let ids = info.founders
                .filter { $0.addr.address.lowercased() == service.address.lowercased() }
                .map{ $0.lockID }
            self.ids = ids
            
        case let .superNode(info):
            let ids = info.founders
                .filter { $0.addr.address.lowercased() == service.address.lowercased() }
                .map{ $0.lockID }
            self.ids = ids

        }
    }
    
    func addLock(info: LockInfo) {
        state = .loading
        Task {
            do {
                let _ = try await service.addLock(id: info.lockID, day: info.selectedLockedDays)
                info.updateInfo()
                state = .success(message: "追加成功".localized)
            }catch{
                state = .failed(error: "追加失败！".localized)
            }
        }
    }
    
    var days: Float = 360
    
    var minimumDays: BigUInt {
        360
    }
    
    var maximumDays: BigUInt {
        3600
    }
    
    var step: BigUInt {
        360
    }
    
    var blockNum: BigUInt {
        2880
    }
    
    func requestLockRecoardInfos() {
        Task { [service, ids] in
            var results: [LockInfo] = []
            var errors: [Error] = []
            await withTaskGroup(of: Result<LockInfo, Error>.self) { taskGroup in
                for id in ids {
                    taskGroup.addTask {
                        do {
                            var lockedDays: BigUInt = 0
                            let record = try await service.getRecordByID(id: id)
                            if let lastBlockHeight = service.lastBlockHeight {
                                if record.unlockHeight >= lastBlockHeight {
                                    let totalLockedHeight = record.unlockHeight - lastBlockHeight
                                    if totalLockedHeight > 0 {
                                        lockedDays = BigUInt(ceil(Double(totalLockedHeight / self.blockNum)))
                                    }
                                }
                            }
                            let maxLockDay = self.maximumDays > lockedDays ? self.maximumDays - lockedDays : 0
                            let item = LockInfo(lockID: id, lockedDays: lockedDays, maxLockDays: maxLockDay, selectedLockedDays: min(maxLockDay, self.step))
                            return .success(item)
                        }catch{
                            return .failure(AddLockDaysError.getInfo)
                        }
                    }
                }
                for await result in taskGroup {
                    switch result {
                    case let .success(value):
                        results.append(value)
                    case let .failure(error):
                        errors.append(error)
                    }
                }
            }
            state = .dataArray(infos: results)
        }
    }
}
extension AddLockDaysViewModel {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }
}
extension AddLockDaysViewModel {

    enum State {
        case loading
        case dataArray(infos: [LockInfo])
        case success(message: String?)
        case failed(error: String?)
    }
    
    enum AddLockDaysError: Error {
        case getInfo
    }
    
    class LockInfo {
        var lockID: BigUInt
        var lockedDays: BigUInt
        var maxLockDays: BigUInt
        var selectedLockedDays: BigUInt
        
        init(lockID: BigUInt, lockedDays: BigUInt, maxLockDays: BigUInt, selectedLockedDays: BigUInt) {
            self.lockID = lockID
            self.lockedDays = lockedDays
            self.maxLockDays = maxLockDays
            self.selectedLockedDays = selectedLockedDays
        }
        
        var step: BigUInt {
            360
        }
        
        func minus(){
            let minDays = min(maxLockDays, step)
            selectedLockedDays = max(selectedLockedDays - min(selectedLockedDays, step), minDays)
        }
        
        func plus(){
            selectedLockedDays = min(selectedLockedDays + step, maxLockDays)
        }
        
        func updateInfo() {
            self.lockedDays += self.selectedLockedDays
            self.maxLockDays -= self.selectedLockedDays
        }
    }
}
