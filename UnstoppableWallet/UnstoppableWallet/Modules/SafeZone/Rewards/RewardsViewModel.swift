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
            DispatchQueue.main.async { [weak self] in
                self?.state = .loading
            }
            
        case let .completed(datas):
            let lastTimestamp = lastTimestamp
            DispatchQueue.global(qos: .userInitiated).async {
                let dateFormatter = DateFormatter.cachedFormatter(format: "yyyy-MM-dd")
                let tempArr = datas.enumerated().map { index, reward in
                    let timestamp = dateFormatter.date(from: reward.date)?.timeIntervalSince1970
                    let isRewarded = timestamp.map { ts in
                        guard let lastTimestamp else {
                            return false
                        }
                        return ts <= lastTimestamp
                    } ?? false

                    return RewardsViewModel.ViewItem(
                        id: "\(reward.date)-\(reward.amount)-\(index)",
                        date: reward.date,
                        amount: reward.amount,
                        withdrawEnabled: !isRewarded
                    )
                }

                DispatchQueue.main.async { [weak self] in
                    self?.state = .completed(tempArr)
                }
            }
            
        case .failed:
            DispatchQueue.main.async { [weak self] in
                self?.state = .completed([])
            }
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
                DispatchQueue.main.async { [weak self] in
                    self?.sendState = .failed(RequestError.withdrawError)
                    self?.onSuccess?(self?.sendState ?? .failed(RequestError.withdrawError))
                }
            }
        }
    }
}

extension RewardsViewModel {
    struct ViewItem: Identifiable {
        let id: String
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
