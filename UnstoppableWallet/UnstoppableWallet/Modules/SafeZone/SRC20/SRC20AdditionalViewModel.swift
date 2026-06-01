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
    let securityCheckViewModel: AddressSecurityCheckViewModel
    private let type: DeployType
    private let service: SRC20Service
    private var disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    private let decimalParser = AmountDecimalParser()
    private let parserChain: AddressParserChain = AddressParserFactory.parserChain(blockchainType: .safe4)
    @Published private(set) var totalSupply: BigUInt?

    @Published var addressResult: AddressInput.Result = .idle
    @Published var addressCautionState: CautionState = .none
    @Published var sendState: SendState = .notReady
    @Published private(set) var checkedResolvedAddress: ResolvedAddress?
    @Published private(set) var addressSecurityState: AddressSecurityCheckViewModel.State = .idle

    init(token: Safe4CustomTokenRecord, service: SRC20Service) {
        self.token = token
        self.type = token.deployType
        self.service = service
        self.securityCheckViewModel = AddressSecurityCheckViewModel(token: Core.shared.evmBlockchainManager.baseToken(blockchainType: .safe4)!)
        self.address = token.creator

        securityCheckViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.syncFromCheckState(state)
            }
            .store(in: &cancellables)
        
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

        if !address.isEmpty {
            validateAddress(address: address)
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

    var addressIssueTypes: [AddressSecurityIssueType] {
        checkedResolvedAddress?.issueTypes ?? []
    }

    var isAddressChecking: Bool {
        if case .checking = addressSecurityState {
            return true
        }

        return false
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
    private func syncAddressSecurityState() {
        switch addressResult {
        case .idle, .loading, .invalid:
            checkedResolvedAddress = nil
            addressSecurityState = .idle
            securityCheckViewModel.check(address: nil)
        case let .valid(success):
            securityCheckViewModel.check(address: success.address)
        }
    }

    private func syncFromCheckState(_ checkState: AddressSecurityCheckViewModel.State) {
        addressSecurityState = checkState

        switch checkState {
        case .idle, .checking:
            checkedResolvedAddress = nil
        case let .completed(address, detectedTypes):
            checkedResolvedAddress = ResolvedAddress(address: address.raw, issueTypes: detectedTypes)
        }
    }

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
            syncAddressSecurityState()
            syncSendData()
            return
        }

        addressResult = .valid(.init(address: address, uri: uri))
        addressCautionState = .none
        syncAddressSecurityState()
        syncSendData()
    }

    private func sync(_ error: Error, text: String) {
        addressResult = .invalid(.init(text: text, error: error))
        let caution = Caution(text: "watch_address.error.not_supported".localized, type: .error)
        addressCautionState = .caution(caution)
        syncAddressSecurityState()
        syncSendData()
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
