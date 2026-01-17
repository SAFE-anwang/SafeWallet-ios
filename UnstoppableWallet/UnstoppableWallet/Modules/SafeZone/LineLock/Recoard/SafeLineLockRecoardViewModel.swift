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
    private(set) var sections = [TransactionsViewModel.Section]()
    private var cancellables = Set<AnyCancellable>()
    private let disposeBag = DisposeBag()
    private let tsVM: TransactionsViewModel
    private var lastSection: TransactionsViewModel.Section?
    private var lastViewItem: TransactionsViewModel.ViewItem?
    private let queue = DispatchQueue(label: "\(AppConfig.label).SafeLineLockRecoard", qos: .userInitiated)
    init(tsVM: TransactionsViewModel) {
        self.tsVM = tsVM
        self.sections = tsVM.sections
        
        tsVM.$sections
        .sink { newSections in
            if let lastSection = newSections.last, let viewItem = lastSection.viewItems.last {
                if self.lastSection != lastSection, self.lastViewItem != viewItem {
                    self.lastSection = lastSection
                    self.lastViewItem = viewItem
                    self.sync(items: tsVM.__items)
                    self.loadMore()
                }
            }
        }
        .store(in: &cancellables)
    }
    
    private func sync(items: [TransactionsViewModel.Item]) {
        queue.async {
            self._sync(items: items)
        }
    }
    func loadMore() {
        if let lastSection, let lastViewItem {
            tsVM.onDisplay(section: lastSection, viewItem: lastViewItem)
        }
    }
    
    private func _sync(items: [TransactionsViewModel.Item]) {
        let itemArray = items
            .unique(by: \.transactionItem.record.uid)
            .map{$0.record as? ContractCallTransactionRecord}
            .filter{$0 != nil}
        
        var total: BigUInt = 0
        var tempViewItems: [LineLockRecoard] = []
        for item in itemArray {
            if let input = item?.transaction.input  {
                let methodId = Data(input.prefix(4)).hs.hexString
                if methodId.lowercased() == EvmLabelManager.ExSafe4Methods.lineLock.id.lowercased(), let method = try? Safe4LineLockMethod.createMethod(inputArguments: Data(input.suffix(from: 4))) as? Safe4LineLockMethod {
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
        if tempViewItems.count == 0 {
            loadMore()
        }else {
            DispatchQueue.main.async { [weak self] in
                self?.totalLockedSafe = total
                self?.viewItems = tempViewItems
            }

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
