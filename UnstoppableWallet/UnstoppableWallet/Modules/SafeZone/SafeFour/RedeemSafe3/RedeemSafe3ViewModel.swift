
import Foundation
import EvmKit
import UIKit
import RxSwift
import RxRelay
import RxCocoa
import HsToolKit
import MarketKit
import BigInt
import web3swift
import Web3Core
import HsExtensions
import ThemeKit
import BitcoinCore
import ComponentKit
import CryptoKit
import BitcoinKit
import HsCryptoKit

class RedeemSafe3ViewModel {
    private let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    private let keyRedeemAddress = "redeem-safe3-address"
    private let disposeBag = DisposeBag()
    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "\(AppConfig.label).redeem-safe3-service")

    private let safe4EvmKitWrapper: EvmKitWrapper
    private let service: RedeemSafe3Service
    private let userDefaultsStorage: UserDefaultsStorage

    private var safe4Page = Safe4PageControl(initCount: 30, totalNum: 0, page: 0, isReverse: false)
    let redeemWalletType: RedeemSafe3Module.RedeemWalletType

    private var availableSafe3Info: AvailableSafe3Info?

    private(set) var existAvailable = false
    private(set) var existLocked = false
    private(set) var existMasterNode = false
    
    private let addressService: AddressService
    
    private(set) var safe3Address: String?
    
    private(set) var privateKeyData: Data?
    private(set) var privateKey: String? {
        didSet {
            if privateKey != oldValue {
                privateKeyRelay.accept(privateKey)
            }
        }
    }

    private(set) var safe4Address: String? {
        didSet {
            safe4AddressRelay.accept(safe4Address)
        }
    }
    
    private(set) var state: SendState = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private(set) var step: RedeemStep = .validated {
        didSet {
            if step != oldValue {
                stepRelay.accept(step)
            }
        }
    }
    
    private(set) var safe3BalanceInfo: Safe3BalanceInfo? {
        didSet {
            safe3BalanceRelay.accept(safe3BalanceInfo)
        }
    }
    
    private var stateRelay = PublishRelay<SendState>()
    private var stepRelay = PublishRelay<RedeemStep>()
    private var safe4AddressRelay = BehaviorRelay<String?>(value: nil)
    private var safe3BalanceRelay = BehaviorRelay<Safe3BalanceInfo?>(value: nil)
    private var isEnabledSendRelay = BehaviorRelay<Bool>(value: false)
    
    private let privateKeyRelay = BehaviorRelay<String?>(value:nil)
    private let privateKeyCautionRelay = BehaviorRelay<Caution?>(value:nil)

    init(service: RedeemSafe3Service, addressService: AddressService, safe4EvmKitWrapper: EvmKitWrapper, /*safe3Adapter: SafeCoinAdapter, safe3Wallet: Wallet, */redeemWalletType: RedeemSafe3Module.RedeemWalletType) {
        self.service = service
        self.safe4EvmKitWrapper = safe4EvmKitWrapper
        self.addressService = addressService
        self.redeemWalletType = redeemWalletType
        self.userDefaultsStorage = UserDefaultsStorage()
        
    }

    private func syncState() {
        if privateKeyData != nil, safe3BalanceInfo == nil {
            step = .check
        }else if safe3BalanceInfo != nil {
            step = .redeem
        }
        syncIsEnabledSend()
    }
    
    private func syncSafe3Info(safe3Address: String) {
        state = .loading
        Task { [service] in
            do {
                try await checkNeedToRedeem(address: safe3Address)
                let info = try await service.safe3GetAvailableInfo(safe3address: safe3Address)
                let (maxLockedCount, results) = try await getLockedSafe3Infos(safe3address: safe3Address)
                let balance = info.amount
                let lockBalance = results.map{$0.amount}.reduce(0, +)
                let masterNodeLockBalance = results.filter{$0.isMN}.map{$0.amount}.reduce(0, +)
                if results.count == 0 {
                    self.existLocked = false
                }
                if lockBalance == 0 {
                    self.existLocked = false
                }
                self.safe3BalanceInfo = Safe3BalanceInfo(maxLockedCount: maxLockedCount, balance: balance, lockBalance: lockBalance, masterNodeLockBalance: masterNodeLockBalance)
                syncState()
                state = .success
            }catch{
                state = .failed(error: "safe_zone.safe4.redeem.balance.info.fail".localized)
                self.safe3BalanceInfo = nil
                syncState()
            }
        }
    }
    
    private func getLockedSafe3Infos(safe3address: String) async throws -> (Int, [LockedSafe3Info] ){
        let lockedNum = try await service.safe3GetLockedNum(safe3address: safe3address)
        safe4Page.set(totalNum: Int(lockedNum))
        guard safe4Page.totalNum > 0 else { return  (0, []) }
        
        var results: [LockedSafe3Info] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<[LockedSafe3Info], Error>.self) { taskGroup in
            for page in safe4Page.pageArray {
                taskGroup.addTask { [self] in
                    do {
                        guard let start = page.first else{ return .failure(RedeemError.getsafe3LockInfoError) }
                        let infos = try await service.safe3GetLockedInfo(safe3address: safe3address, start: BigUInt(start), count: BigUInt(page.count))
                        return .success(infos)
                    }catch{
                        return .failure(RedeemError.getsafe3LockInfoError)
                    }
                }
            }
            for await result in taskGroup {
                switch result {
                case let .success(value):
                    results.append(contentsOf: value)
                case let .failure(error):
                    errors.append(error)
                }
            }
        }
        return (Int(lockedNum), results)
    }
    
    private func syncIsEnabledSend() {
        guard safe3BalanceInfo != nil else {return isEnabledSendRelay.accept(false)}
        var isRedeem = false
        if let privateKeyData, let redeem: Bool = userDefaultsStorage.value(for: "\(keyRedeemAddress)\(privateKeyData.hs.hex)") {
            isRedeem = redeem
        }
        let isEnabled = (existAvailable || existLocked) && !isRedeem
        isEnabledSendRelay.accept(isEnabled)
    }
}

extension RedeemSafe3ViewModel {
    
    func onEnter(safe3PrivateKey: String?) {
        if let inputString = safe3PrivateKey {
            let privateKey = wifToHexPrivateKey(inputString) ?? inputString

            let privateKeyData: Data?
            if privateKey.hasHexPrefix(), privateKey.count == 66 {
                privateKeyData = privateKey.hs.hexData
            } else if !privateKey.hasHexPrefix(), privateKey.count == 64 {
                privateKeyData = ("0x" + privateKey).hs.hexData
            } else {
                privateKeyData = nil
            }
            self.privateKeyData = privateKeyData
            syncState()
        }else {
            self.safe4Address = nil
            self.privateKeyData = nil
            self.safe3BalanceInfo = nil
        }
        
        if privateKeyData != nil {
            self.step = .check
        } else {
            self.step = .validated
        }
    }
    
    func validate(privateKey: String?) {
        guard (privateKey?.count ?? 0) > 0 else{ return }
        self.safe4Address = nil
        guard let privateKeyData else {
            syncState()
            self.safe3BalanceInfo = nil
            self.step = .check
            privateKeyCautionRelay.accept(Caution(text: "safe_zone.safe4.redeem.private.verify.fail".localized, type: .error))
            return
        }
        let safe3Address = privateKeyToSafe3Address(privateKey: privateKeyData)
        self.safe3Address = safe3Address
        self.safe4Address = privateKeyToSafe4Address(privateKey: privateKeyData)
        syncSafe3Info(safe3Address: safe3Address)
        syncState()
    }
    
    func redeem() {
        guard let privateKey = privateKeyData else { return }
        redeem(privateKey: privateKey)
    }
    
    func redeem(privateKey: Data) {
        guard let safe4Address else { return }
        state = .loading
        Task { [self, service] in
            do {
                guard let callerPrivateKey = safe4EvmKitWrapper.signer?.privateKey else { return }
                let results = try await service.redeemSafe3(callerPrivateKey: callerPrivateKey, privateKeys: [privateKey], targetAddr: safe4Address)
                guard let result = results.first, result.count > 0 else{
                    return state = .failed(error: "safe_zone.safe4.redeem.balance.fail".localized)
                }
                if existMasterNode {
                    let result = try await service.redeemMasterNode(callerPrivateKey: callerPrivateKey, privateKeys: [privateKey], enodes: [""], targetAddr: safe4Address)
                    guard result.count > 0 else{
                        return state = .failed(error: "safe_zone.safe4.redeem.master.fail".localized)
                    }
                }
                userDefaultsStorage.set(value: true, for: keyRedeemAddress + "\(privateKey.hs.hex)")
                step = .sent
                state = .sent
            }catch{
                state = .failed(error: "safe_zone.safe4.redeem.fail".localized)
            }
        }
    }
}

// localWallet
extension RedeemSafe3ViewModel {
    
    func syncLocalWalletInfo(safe3Wallet: Wallet, safe3Adapter: SafeCoinAdapter) {
        self.step = .validated
        if case .local = redeemWalletType {
            state = .loading
            Task {[weak self, service] in
                guard let self = self else { return }
                do {
                    let masterPrivateKey = try safe3Adapter.masterPrivateKey(wallet: safe3Wallet)
                    let hdWallet = try safe3Adapter.hdWallet(safe3Wallet)

                    self.step = .check
                    let unspentOutputs = safe3Adapter.bitcoinCore.storage.unspentOutputs()
                    let uniqueArray = unspentOutputs.reduce(into: [String: [UnspentOutput]]()) { result, output in
                        if let key = output.transaction.blockHash?.hs.hexString {
                            if result[key] == nil {
                                result[key] = []
                            }
                            if !result[key]!.contains(where: { $0.transaction.blockHash?.hs.hexString == key }) {
                                result[key]!.append(output)
                            }
                        }
                    }.flatMap{$0.value}
                    
                    var results: [LocalSafe3WalletBalanceInfoItem] = []
                    var errors: [Error] = []
                    await withTaskGroup(of: Result<LocalSafe3WalletBalanceInfoItem, Error>.self) { taskGroup in
                        for unspentOutput in uniqueArray {
                            taskGroup.addTask {
                                do {
                                    let address = try safe3Adapter.bitcoinCore.address(from: unspentOutput.publicKey).stringValue
                                    async let existAvailable = try service.existAvailableNeedToRedeem(safe3address: address)
                                    async let existLocked = try service.existLockedNeedToRedeem(safe3Addr: address)
                                    async let existMasterNode = try service.existMasterNodeNeedToRedeem(safe3Addr: address)
                                    let info = try await service.safe3GetAvailableInfo(safe3address: address)
                                    let (maxLockedCount, results) = try await self.getLockedSafe3Infos(safe3address: address)
                                    let balance = info.amount
                                    let lockBalance = results.map{$0.amount}.reduce(0, +)
                                    let pubKey = unspentOutput.publicKey
                                    guard let subPrivateKey = try? hdWallet.privateKey(account: pubKey.account, index: pubKey.index, chain: .external).raw else {
                                        throw RedeemError.getBalanceInfoError
                                    }
                                    let subAddr = self.privateKeyToSafe3Address(privateKey: subPrivateKey)
                                    
                                    guard address == subAddr else { throw RedeemError.getBalanceInfoError }

                                    let item = try await LocalSafe3WalletBalanceInfoItem(address: address, maxLockedCount: maxLockedCount, balance: balance, lockBalance: lockBalance, existAvailable: existAvailable, existLocked: existLocked, existMasterNode: existMasterNode, privateKey: subPrivateKey)
                                    return .success(item)
                                }catch{
                                    return .failure(RedeemError.getBalanceInfoError)
                                }
                            }
                        }
                        for await result in taskGroup {
                            switch result {
                            case let .success(value):
                                results.append(value)
                            case let .failure(error):
                                errors.append(error)
                            }
                        }
                    }
                    results.sort{ ($0.address.hs.hexData ?? Data()) > ($1.address.hs.hexData ?? Data()) }
                    self.state = .complated(datas: results)
                    self.step = .redeem
                    self.privateKeyData = masterPrivateKey.raw
                    self.privateKey = masterPrivateKey.raw.hs.hex
                    self.safe4Address = safe4EvmKitWrapper.evmKit.receiveAddress.hex
                    let isEnabled = results.filter{ $0.isEnabledRedeem }.count > 0
                    self.isEnabledSendRelay.accept(isEnabled)
                }catch {
                    self.state = .failed(error: "safe_zone.safe4.redeem.fund.query.fail".localized)
                }
            }
        }
    }
    
    func loalWalletRedeem(items: [LocalSafe3WalletBalanceInfoItem]) {
        guard let safe4Address else { return }
        guard let callerPrivateKey = safe4EvmKitWrapper.signer?.privateKey else { return }
        let privateKeyArray = items.filter{ $0.isEnabledRedeem && !$0.existMasterNode }.map{ $0.privateKey}
        let masterNodeArray = items.filter{ $0.existMasterNode}.map{ $0.privateKey}
        state = .loading
        Task {[weak self, service] in
            guard let self = self else { return }
            do {
                let results = try await service.redeemSafe3(callerPrivateKey: callerPrivateKey, privateKeys: privateKeyArray, targetAddr: safe4Address)
                if masterNodeArray.count > 0 {
                    let enodes = masterNodeArray.map{_ in ""}
                    let result = try await service.redeemMasterNode(callerPrivateKey: callerPrivateKey, privateKeys: masterNodeArray, enodes: enodes, targetAddr: safe4Address)
                }
            }catch {
                self.state = .failed(error: "资产迁移失败".localized)
            }
        }
    }
}

extension RedeemSafe3ViewModel {
    var privateKeyDriver: Driver<String?> {
        privateKeyRelay.asDriver()
    }
    var privateKeyCautionDriver: Driver<Caution?> {
        privateKeyCautionRelay.asDriver()
    }
    
    var safe3BalanceDriver: Driver<Safe3BalanceInfo?> {
        safe3BalanceRelay.asDriver()
    }
    
    var safe4AddressDriver: Driver<String?> {
        safe4AddressRelay.asDriver()
    }
    
    var stateDriver: Observable<SendState> {
        stateRelay.asObservable()
    }
    
    var stepDriver: Observable<RedeemStep> {
        stepRelay.asObservable()
    }
    
    var isEnabledSendDriver: Observable<Bool> {
        isEnabledSendRelay.asObservable()
    }
}

extension RedeemSafe3ViewModel {
        
    private func checkNeedToRedeem(address: String) async throws {
        async let existAvailable = try service.existAvailableNeedToRedeem(safe3address: address)
        async let existLocked = try service.existLockedNeedToRedeem(safe3Addr: address)
        async let existMasterNode = try service.existMasterNodeNeedToRedeem(safe3Addr: address)
        self.existAvailable = try await existAvailable
        self.existLocked = try await existLocked
        self.existMasterNode = try await existMasterNode
    }
    
    private func privateKeyToSafe4Address(privateKey: Data) -> String {
        return EvmKit.Signer.address(privateKey: privateKey).eip55
    }
    
    private func privateKeyToSafe3Address(privateKey: Data) -> String {
        let compressedPublicKey = Safe3Util.getCompressedPublicKey(privateKey)
        let compressedSafe3Addr = Safe3Util.getSafe3Addr(compressedPublicKey)
        return compressedSafe3Addr
    }
}

extension RedeemSafe3ViewModel {
    
    struct LocalSafe3WalletBalanceInfoItem {
        let address: String
        let maxLockedCount: Int
        let balance: BigUInt
        let lockBalance: BigUInt
        let existAvailable: Bool
        let existLocked: Bool
        let existMasterNode: Bool
        let privateKey: Data
        
        var isEnabledRedeem: Bool {
            existAvailable || existLocked
        }
    }
    
    struct Safe3BalanceInfo {
        let maxLockedCount: Int
        let balance: BigUInt
        let lockBalance: BigUInt
        let masterNodeLockBalance: BigUInt
        
        var hasBalance: Bool {
            balance + lockBalance + masterNodeLockBalance > 0
        }
    }
    
    enum RedeemStep: Int, Equatable {
        case validated = 1
        case check = 2
        case redeem = 3
        case sent = 4
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.validated, .validated): return true
            case (.check, .check): return true
            case (.redeem, .redeem): return true
            case (.sent, .sent): return true
            default: return false
            }
        }
    }
    
    enum SendState: Equatable {
        case loading
        case success
        case complated(datas: [RedeemSafe3ViewModel.LocalSafe3WalletBalanceInfoItem])
        case sent
        case failed(error: String)
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.success, .success): return true
            case (.sent, .sent): return true
            case let (.failed(lh), .failed(rh)): return lh == rh
            default: return false
            }
        }
    }
    
    enum Safe3SyncState: Equatable {
        case loading
        case success
        case complated(datas: [RedeemSafe3ViewModel.LocalSafe3WalletBalanceInfoItem])
        case sent
        case failed(error: String)
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.success, .success): return true
            case (.sent, .sent): return true
            case let (.failed(lh), .failed(rh)): return lh == rh
            default: return false
            }
        }
    }
    
    enum RedeemError: Error {
        case getsafe3LockInfoError
        case privateKeyError
        case safe4AddressError
        case getBalanceInfoError
        case redeemFaild
        case subPrivateKeyError
    }
}

private extension RedeemSafe3ViewModel {
    func wifToHexPrivateKey(_ wif: String) -> String? {
        let decode = Base58.decode(wif).hs.hex
        guard decode.count >= 66 else { return nil }
        let privateKey = decode[2...65]
        return privateKey
    }
}
