import Combine
import Foundation
import HsExtensions
import web3swift
import Web3Core
import BigInt
import RxCocoa
import RxSwift
import BitcoinCore
import EvmKit

class SafeLineLockRecoardViewModel: ObservableObject {
    @Published var totalLockedSafe: BigUInt = 0
    @Published private(set) var viewItems: [LineLockRecoard] = []
    private var index: Int = 0
    private var tempItemDatas = [TransactionsService.ItemData]()
    private let service: TokenTransactionsService
    private let factory: TransactionsViewItemFactory
    private let disposeBag = DisposeBag()
    private let queue = DispatchQueue(label: "\(AppConfig.label).base_transactions_view_model", qos: .userInitiated)

    init(service: TokenTransactionsService, factory: TransactionsViewItemFactory) {
        self.service = service
        self.factory = factory
    
        subscribe(disposeBag, service.itemDataObservable) { [weak self] in self?.sync(itemData: $0) }
    }
    
    private func sync(itemData: TransactionsService.ItemData) {
        queue.async {
            self._sync(itemData: itemData)
        }
    }
    
    private func _sync(itemData: TransactionsService.ItemData) {
        index += itemData.items.count
        tempItemDatas.append(itemData)
        if itemData.items.count == 20 {
            service.loadMoreIfRequired(index: index)
            service.fetchRate(index: index)
        }
        let items = tempItemDatas
            .flatMap{ $0.items }
            .unique(by: \.transactionItem.record.uid)
            .filter{ $0.record is ContractCallTransactionRecord }
            .map { factory.viewItem(item: $0, balanceHidden: service.balanceHidden) }

        var total: BigUInt = 0
        var tempViewItems: [LineLockRecoard] = []
        for item in items {
            if let input = item.input {
                let methodId = Data(input.prefix(4)).hs.hexString
                if methodId == EvmLabelManager.ExSafe4Methods.lineLock.id {
                    let inputArguments = Data(input.suffix(from: 4))
                    let parsedArguments = ContractMethodHelper.decodeABI(inputArguments: inputArguments, argumentTypes: [EvmKit.Address.self, BigUInt.self, BigUInt.self, BigUInt.self])
                    guard let address = parsedArguments[0] as? EvmKit.Address,
                          let times = parsedArguments[1] as? BigUInt,
                          let spaceDay = parsedArguments[2] as? BigUInt,
                          let startDay = parsedArguments[3] as? BigUInt else {
                            return
                    }
                    if let value = item.value {
                        total += value
                        let lockedValue = value / times
                        for i in 1 ... times {
                            let month = (startDay + i * spaceDay) / 30
                            let item = LineLockRecoard(value: lockedValue, month: Int(month), address: address.eip55)
                            tempViewItems.append(item)
                        }

                    }
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.totalLockedSafe = total
            self?.viewItems = tempViewItems
        }
    }
}

extension SafeLineLockRecoardViewModel {
    struct LineLockRecoard: Hashable, Identifiable {
        let value: BigUInt
        let month: Int
        let address: String
        
        var lockedSafe: String {
            "\(value.safe4FomattedAmount)"
        }
        
        var id: Self {
            self
        }
    }
}

extension Array {
    func unique<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { element in
            let key = element[keyPath: keyPath]
            if seen.contains(key) {
                return false
            } else {
                seen.insert(key)
                return true
            }
        }
    }
}
