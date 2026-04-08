import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt

class SRC20DestroyViewModel: ObservableObject {
    let token: Safe4CustomTokenRecord
    private let type: DeployType
    private let service: SRC20Service
    private let adapter: ISendEthereumAdapter
    private let decimalParser = AmountDecimalParser()
    @Published private(set) var totalSupply: BigUInt?
    @Published var sendState: SendState = .notReady
    @Published var amountCautionState: CautionState = .none

    init(token: Safe4CustomTokenRecord, service: SRC20Service, adapter: ISendEthereumAdapter) {
        self.token = token
        self.type = token.deployType
        self.service = service
        self.adapter = adapter
        
        Task {
            do {
                let totalSupply = try await service.totalSupply(type: token.deployType)
                DispatchQueue.main.async { [weak self] in
                    self?.totalSupply = totalSupply
                }
            }catch{
                print("")
            }
        }
    }
    @Published var numberString: String = "" {
        didSet {
            var number = decimalParser.parseAnyDecimal(from: numberString)

            if number == 0 {
                number = nil
            }
            guard number != self.number else {
                return
            }
            self.number = number
        }
    }
    
    var number: Decimal? {
        didSet {
            syncAmountCautionState()
            syncSendData()
            let number = decimalParser.parseAnyDecimal(from: numberString)

            if number != self.number {
                numberString = self.number?.description ?? ""
            }
        }
    }
    
    var totalSupplyString: String {
        (totalSupply?.safe4FomattedAmount ?? "null") + "  " + token.symbol
    }
    
    var balance: Decimal {
        adapter.balanceData.available
    }
    
    var balanceString: String {
        adapter.balanceData.available.safe4FormattedAmount + "  " + token.symbol
    }
    
    private func syncSendData() {
        guard let number, validateAmountIn() == nil else { return sendState = .notReady }
        let value = BigUInt((number * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        sendState = .ready(value)
    }
    
    @MainActor
    func destroy(onComplete: @escaping (SendState) -> Void) {
        Task{
            do{
                if case let .ready(amount) = sendState {
                    self.sendState = .sending
                    _ = try await service.burn(amount: amount)
                    self.sendState = .completed
                    onComplete(.completed)
                }
            }catch{
                self.sendState = .failed
                onComplete(.failed)
            }
        }
    }
}
extension SRC20DestroyViewModel {
    private func syncAmountCautionState() {
        let caution = validateAmountIn()
        amountCautionState = caution != nil ? .caution(caution!) : .none
    }
    
    private func validateAmountIn() -> Caution? {
        var caution: Caution?
        if let number, !number.isZero {
            if number < 1 {
                caution = Caution(text: "safe_zone.invalid_input".localized, type: .error)

            }else if number > balance {
                caution = Caution(text: "safe_zone.send.insufficientBalance".localized, type: .error)

            }
        }else {
            caution = Caution(text: "safe_zone.invalid_input".localized, type: .error)
        }
        
        return caution
    }
}
extension SRC20DestroyViewModel {
    enum FocusField: Int, Hashable {
        case destroy
    }
    
    enum SendState: Equatable {
        case notReady
        case ready(BigUInt)
        case sending
        case completed
        case failed
        public static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.notReady, .notReady): return true
            case let (.ready(lhsData), .ready(rhsData)): return lhsData == rhsData
            case (.sending, .sending): return true
            case (.completed, .completed): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
}
