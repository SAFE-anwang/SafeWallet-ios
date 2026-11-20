import Foundation
import RxRelay

protocol IAmountPublishService: AnyObject {
    var publishAmountRelay: BehaviorRelay<Decimal>? { get set }
}
