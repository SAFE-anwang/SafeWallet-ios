import Foundation
import BigInt
import RxSwift
import RxRelay
import Web3Core
import web3swift
import Combine

class AddLockDaysViewModel: ObservableObject {
    private let service: AddLockDaysService
    @Published private(set) var state: State = .loading
    @Published private(set) var viewItems: [LockInfo] = []
    private var ids = [BigUInt]()
    
    init(service: AddLockDaysService, ids: [BigUInt]) {
        self.service = service
        self.ids = ids
        requestLockRecoardInfos()
    }
    
    func addLock(info: LockInfo) {
        state = .loading
        Task {
            do {
                let _ = try await service.addLock(id: info.lockID, day: info.selectedLockedDays)
                info.updateInfo()
                DispatchQueue.main.async { [self] in
                    state = .success(message: "追加成功".localized)
                }
            }catch{
                DispatchQueue.main.async { [self] in
                    state = .failed(error: "追加失败！".localized)
                }
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
        state = .loading
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
                            let item = LockInfo(lockID: id, lockedAmount: record.amount, lockedDays: lockedDays, maxLockDays: maxLockDay, selectedLockedDays: min(maxLockDay, self.step))
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
            DispatchQueue.main.async { [self] in
                viewItems = results
                state = .completed
            }
        }
    }
}

extension AddLockDaysViewModel {

    enum State: Equatable {
        case loading
        case completed
        case success(message: String?)
        case failed(error: String?)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.completed, .completed): return true
            case (.success(let lhsMsg), .success(let rhsMsg)):
                return lhsMsg == rhsMsg
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }
    
    enum AddLockDaysError: Error {
        case getInfo
    }
    
    class LockInfo: Identifiable, ObservableObject{
        var lockID: BigUInt
        var lockedAmount: BigUInt
        var lockedDays: BigUInt
        var maxLockDays: BigUInt
        @Published var selectedLockedDays: BigUInt
        
        init(lockID: BigUInt, lockedAmount: BigUInt, lockedDays: BigUInt, maxLockDays: BigUInt, selectedLockedDays: BigUInt) {
            self.lockID = lockID
            self.lockedAmount = lockedAmount
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
