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
    private var withdrawTask: Task<Void, Never>?
    private var networkObservation: Safe4NetworkSession?
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
        networkObservation = Safe4NetworkSession { [weak self] in
            self?.withdrawTask?.cancel()
        }
        refresh()
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(dataState: $0) }
    }

    private var last_Rewards_Timestamp_KEY: String {
        service.cacheScope.key("last_rewards_timestamp")
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
                guard self?.service.networkSession.isValid == true else { return }
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
                    guard self?.service.networkSession.isValid == true else { return }
                    self?.state = .completed(tempArr)
                }
            }

        case .failed:
            DispatchQueue.main.async { [weak self] in
                guard self?.service.networkSession.isValid == true else { return }
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
        guard service.networkSession.isValid, withdrawTask == nil else { return }
        sendState = .loading
        withdrawTask = Task { @MainActor in
            defer { withdrawTask = nil }
            do{
                try await service.withdrawByID()
                try service.networkSession.check()
                try Task.checkCancellation()
                let dateFormatter = DateFormatter.cachedFormatter(format: "yyyy-MM-dd")
                let date = dateFormatter.string(from: Date())
                lastTimestamp = dateFormatter.date(from: date)?.timeIntervalSince1970
                DispatchQueue.main.async { [self] in
                    guard service.networkSession.isValid else { return }
                    sendState = .completed
                    onSuccess?(sendState)
                }
            }catch{
                DispatchQueue.main.async { [weak self] in
                    guard self?.service.networkSession.isValid == true else { return }
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
