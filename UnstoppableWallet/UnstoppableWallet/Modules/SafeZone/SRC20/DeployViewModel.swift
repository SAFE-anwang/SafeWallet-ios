import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt

class DeployViewModel: ObservableObject {
    
    private let decimalParser = AmountDecimalParser()
    private let evmKitWrapper: EvmKitWrapper
    private let service: SRC20Service
    private var disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var nameCautionState: CautionState = .none
    @Published var symbolCautionState: CautionState = .none
    @Published var totalSupplyCautionState: CautionState = .none
    @Published var sendState: SendState = .notReady
    
    @Published var mode: DeployType = .SRC20
    @Published var name: String = "" {
        didSet {
            syncSendData()
        }
    }
    
    @Published var symbol: String  = "" {
        didSet {
            syncSendData()
        }
    }
    
    @Published var totalSupplyString: String = "" {
        didSet {
            var totalSupply = decimalParser.parseAnyDecimal(from: totalSupplyString)

            if totalSupply == 0 {
                totalSupply = nil
            }
            guard totalSupply != self.totalSupply else {
                return
            }
            self.totalSupply = totalSupply
        }
    }
    
    var totalSupply: Decimal? {
        didSet {
//            syncAmountCautionState()
            syncSendData()

            let totalSupply = decimalParser.parseAnyDecimal(from: totalSupplyString)

            if totalSupply != self.totalSupply {
                totalSupplyString = self.totalSupply?.description ?? ""
            }
        }
    }

    init(service: SRC20Service, evmKitWrapper: EvmKitWrapper) {
        self.service = service
        self.evmKitWrapper = evmKitWrapper
    }
    
    private func syncSendData() {
        sendState = .notReady
        guard let totalSupply else { return }
        guard !name.isEmpty, !symbol.isEmpty, totalSupply > 0 else { return }
        sendState = .ready
    }
    
    func deploy(onComplete: @escaping (SendState) -> Void) {
        sendState = .sending
        guard let totalSupply else{ return }
        let value = BigUInt((totalSupply * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        Task {
            do{
                _ = try await service.deploy(type: mode, name: name, symbol: symbol, totalSupply: value)
                DispatchQueue.main.async {
                    self.sendState = .completed
                    onComplete(self.sendState)
                }
            }catch{ 
                DispatchQueue.main.async {
                    self.sendState = .ready
                    onComplete(self.sendState)
                }
            }
        }
    }
    
    func choosed(mode: DeployType) {
        self.mode = mode
    }
}

extension DeployViewModel {
    enum FocusField: Int, Hashable {
        case name
        case symbol
        case totalSupply
    }
    
    enum SendState: Equatable {
        case notReady
        case ready
        case sending
        case completed
        case failed
        public static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.notReady, .notReady): return true
            case (.ready, .ready): return true
            case (.sending, .sending): return true
            case (.completed, .completed): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
}
