import RxSwift
import RxRelay
import RxCocoa
import HsToolKit
import MarketKit
import BigInt
import web3swift
import Web3Core
import HsExtensions
import Combine
import Foundation

class RewardsViewModel: ObservableObject {
    
    private let service: RewardsService
    private let disposeBag = DisposeBag()
    private var userDefaultsStorage = UserDefaultsStorage()
    
    @Published private(set) var state: DataStatus<[ViewItem]> = .loading
    @Published private(set) var sendState: SendStatus = .normal
    
    var withdrawEnabled: Bool {
        if case .loading = sendState {
                return false
        }
        if case .loading = state {
            return false
        }
        
        if  case let .completed(items) = state {
            return items.filter{$0.withdrawEnabled}.count > 0 ? true : false
        }
        return true
    }
    
    var onSuccess: ((SendStatus) -> Void)?
    
    init(service: RewardsService) {
        self.service = service
        refresh()
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(dataState: $0) }
    }
    
    private var last_Rewards_Timestamp_KEY: String {
        "last_Rewards_Timestamp_key_\(service.address)"
    }
    
    var lastTimestamp: TimeInterval? {
        get {
            let timestamp: TimeInterval? = userDefaultsStorage.value(for: last_Rewards_Timestamp_KEY)
            return timestamp
        }
        set { userDefaultsStorage.set(value: newValue, for: last_Rewards_Timestamp_KEY) }
    }

    private func sync(dataState: RewardsService.State) {
        switch dataState {
        case .loading:
            state = .loading
            
        case let .completed(datas):
            DispatchQueue.main.async { [self] in
                let tempArr = datas.map {
                    let timestamp = DateFormatter.cachedFormatter(format: "yyyy-MM-dd").date(from: $0.date)?.timeIntervalSince1970
                    let isRewarded = isRewarded(timestamp: timestamp)
                    return RewardsViewModel.ViewItem(date: $0.date,
                                                     amount: $0.amount,
                                                     withdrawEnabled: !isRewarded
                    )
                }
                state = .completed(tempArr)
            }
            
        case .failed:
            state = .completed([])
        }
    }
}

extension RewardsViewModel {
    func refresh() {
        service.refresh()
    }
    
    func withdraw() {
        sendState = .loading
        Task {
            do{
                try await service.withdrawByID()
                let dateFormatter = DateFormatter.cachedFormatter(format: "yyyy-MM-dd")
                let date = dateFormatter.string(from: Date())
                lastTimestamp = dateFormatter.date(from: date)?.timeIntervalSince1970
                DispatchQueue.main.async { [self] in
                    sendState = .completed
                    onSuccess?(sendState)
                }
            }catch{
                sendState = .failed(RequestError.withdrawError)
                onSuccess?(sendState)
            }
        }
    }

    private func isRewarded(timestamp: TimeInterval?) -> Bool {
        guard let timestamp, let lastTimestamp = lastTimestamp else { return false }
        return timestamp <= lastTimestamp
    }
    
}

extension RewardsViewModel {
    struct ViewItem {
        let date: String
        let amount: String
        let withdrawEnabled: Bool
        
        var amountStr: String {
            "\(BigUInt(amount)?.safe4Amount(decimalCount: 8) ?? "-") SAFE"
        }

    }
    
    enum SendStatus {
        case normal
        case loading
        case failed(Error)
        case completed
    }
    
    enum RequestError: Error {
        case withdrawError
    }
}

