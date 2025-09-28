import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt
import web3swift
import Web3Core

class SRC20AdditionalViewModel: ObservableObject {
    let token: Safe4CustomTokenRecord
    private let type: DeployType
    private let service: SRC20Service
    private var disposeBag = DisposeBag()
    private let decimalParser = AmountDecimalParser()
    private let parserChain: AddressParserChain = AddressParserFactory.parserChain(blockchainType: .safe4)
    @Published private(set) var totalSupply: BigUInt?

    @Published var addressResult: AddressInput.Result = .idle
    @Published var addressCautionState: CautionState = .none
    @Published var sendState: SendState = .notReady

    init(token: Safe4CustomTokenRecord, service: SRC20Service) {
        self.token = token
        self.type = token.deployType
        self.service = service
        self.address = token.creator
        
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
    
    @Published var address: String  {
        didSet {
            if address.count > 0 {
                validateAddress(address: address)
            }else {
                addressCautionState = .none
            }
            syncSendData()
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
    var totalSupplyString: String {
        (totalSupply?.safe4FomattedAmount ?? "null") + "  " + token.symbol
    }
    
    var number: Decimal? {
        didSet {
            syncSendData()
            let number = decimalParser.parseAnyDecimal(from: numberString)

            if number != self.number {
                numberString = self.number?.description ?? ""
            }
        }
    }
    
    func syncSendData() {
        guard case let .valid(result) = addressResult, let address = Web3Core.EthereumAddress(result.address.raw) else { return sendState = .notReady }
        guard let number, number > 0 else { return sendState = .notReady }
        let value = BigUInt((number * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        sendState = .ready(SendData(address: address, number: value))
    }
    
    @MainActor
    func update(onComplete: @escaping (SendState) -> Void) {
        Task {
            do{
                if case let .ready(sendData) = sendState {
                    self.sendState = .sending
                    _ = try await service.mint(type: token.deployType, to: sendData.address, amount: sendData.number)
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

// address
extension SRC20AdditionalViewModel {
    private func validateAddress(address: String) {
        parserChain
            .handle(address: address)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .observeOn(MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] in self?.sync($0, uri: nil) },
                onError: { [weak self] in self?.sync($0, text: address) }
            )
            .disposed(by: disposeBag)
    }

    private func sync(_ address: Address?, uri: AddressUri?) {
        guard let address else {
            addressResult = .idle
            return
        }

        addressResult = .valid(.init(address: address, uri: uri))
        addressCautionState = .none
    }

    private func sync(_ error: Error, text: String) {
        addressResult = .invalid(.init(text: text, error: error))
        let caution = Caution(text: "watch_address.error.not_supported".localized, type: .error)
        addressCautionState = .caution(caution)
    }
}

extension SRC20AdditionalViewModel {
    
    struct SendData: Equatable {
        let address: Web3Core.EthereumAddress
        let number: BigUInt
        
        public static func == (lhs: SendData, rhs: SendData) -> Bool {
            lhs.address == rhs.address && lhs.number == rhs.number
        }
    }
    
    enum FocusField: Int, Hashable {
        case address
        case number
    }
    
    enum SendState: Equatable {
        case notReady
        case ready(SendData)
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

