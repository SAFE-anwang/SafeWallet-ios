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
//    private var viewModel: TransactionsViewModel
    private let disposeBag = DisposeBag()
//    private let queue = DispatchQueue(label: "\(AppConfig.label).line_lock_recoard_view_model", qos: .userInitiated)
    private let adapter: ITransactionsAdapter
    init(adapter: ITransactionsAdapter) {
        self.adapter = adapter
//        sync(items: viewModel.__items)
        
        subscribe(disposeBag, adapter.transactionsObservable(token: nil, filter: .all, address: nil)) { [weak self] records in
//            self?.logger?.log(level: .debug, message: "Handle NEW \(records.count) records. For \(source.blockchainType.uid)")
//            self?.serialSync(source: source)
        }
    }
    
//    private func sync(items: [TransactionsViewModel.Item]) {
//        queue.async {
//            self._sync(items: items)
//        }
//    }
    private func _sync(items: [TransactionsViewModel.Item]) {
        let itemArray = items
            .unique(by: \.transactionItem.record.uid)
            .map{$0.record as? ContractCallTransactionRecord}
            .filter{$0 != nil}
        
        var total: BigUInt = 0
        var tempViewItems: [LineLockRecoard] = []
        for item in itemArray {
            if let input = item?.transaction.input  {
                if let method = try? Safe4LineLockMethod.createMethod(inputArguments: input) as? Safe4LineLockMethod {
                    if let value = item?.transaction.value {
                        total += value
                        let lockedValue = value / method.times
                        for i in 1 ... method.times {
                            let month = (method.startDay + i * method.spaceDay) / 30
                            let item = LineLockRecoard(value: lockedValue, month: Int(month), address: method.address.eip55)
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
        let id = UUID()
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
