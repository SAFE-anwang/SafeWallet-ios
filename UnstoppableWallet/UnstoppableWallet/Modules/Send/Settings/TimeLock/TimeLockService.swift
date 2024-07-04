import Hodler
import RxCocoa
import RxRelay
import RxSwift

class TimeLockService {
    private var disposeBag = DisposeBag()

    private let lockTimeRelay = BehaviorRelay<Item>(value: .none)
    var lockTime: Item = .none {
        didSet {
            if oldValue != lockTime {
                lockTimeRelay.accept(lockTime)
                pluginData = pluginData(lockTime: lockTime)
            }
        }
    }

    private let pluginDataRelay = BehaviorRelay<[UInt8: IBitcoinPluginData]>(value: [:])
    var pluginData = [UInt8: IBitcoinPluginData]() {
        didSet {
            pluginDataRelay.accept(pluginData)
        }
    }

    private func pluginData(lockTime: Item) -> [UInt8: IBitcoinPluginData] {
        guard let lockTimeInterval = lockTime.lockTimeInterval else {
            return [:]
        }

        return [HodlerPlugin.id: HodlerData(lockTimeInterval: lockTimeInterval)]
    }

    var lockTimeList = Item.allCases
}

extension TimeLockService {
    var lockTimeObservable: Observable<Item> {
        lockTimeRelay.asObservable()
    }

    var pluginDataObservable: Observable<[UInt8: IBitcoinPluginData]> {
        pluginDataRelay.asObservable()
    }

    func set(index: Int) {
        guard index < lockTimeList.count else {
            return
        }

        lockTime = lockTimeList[index]
    }
}

extension TimeLockService {
    enum Item: UInt16, CaseIterable {
        case none
        case month
        case month_3
        case halfYear
        case month_9
        case year
        case year_3
        case year_5
        case year_10

        var lockTimeInterval: HodlerPlugin.LockTimeInterval? {
            switch self {
            case .none: return nil
            case .month: return .month
            case .month_3: return .month_3
            case .halfYear: return .halfYear
            case .month_9: return .month_9
            case .year: return .year
            case .year_3: return .year_3
            case .year_5: return .year_5
            case .year_10: return .year_10
            }
        }

        var title: String {
            HodlerPlugin.LockTimeInterval.title(lockTimeInterval: lockTimeInterval)
        }
    }
}
