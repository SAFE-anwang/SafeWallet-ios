import Foundation
import RxSwift
import RxRelay
import MarketKit
import UniswapKit
import HsExtensions
import EvmKit
import BigInt
import RxSwift
import RxCocoa
import HsCryptoKit
import Web3Core
import web3swift
import Eip20Kit

class LiquidityRecordService {    
    private let currentBlockchainType: BlockchainType
    private let marketKit: MarketKit.Kit
    private let walletManager: WalletManager
    private let adapterManager: AdapterManager
    private var viewItemsRelay = BehaviorRelay<[LiquidityRecordViewModel.RecordItem]>(value: [])
    private var viewItems = [LiquidityRecordViewModel.RecordItem]()
    private let disposeBag = DisposeBag()
    private let stateRelay = PublishRelay<State>()
    private var ratio: BigUInt = 100
    private var evmKitWrapper: EvmKitWrapper?
    private var legacyGasPrice: GasPrice?
    
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "anwang.safewallet.liquidity_record")

    
    init(marketKit: MarketKit.Kit, walletManager: WalletManager, adapterManager: AdapterManager, blockchainType: BlockchainType) {
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.adapterManager = adapterManager
        
        self.currentBlockchainType = blockchainType
        
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else {
            return
        }
        self.evmKitWrapper = evmKitWrapper
        syncgasPrice(evmKitWrapper: evmKitWrapper)
    }
    
    func refresh() {
        syncItems()
    }
    
    private func syncItems() {        
        let tokenQuerys = activeWallets.compactMap { TokenQuery(blockchainType: $0.token.blockchainType, tokenType: $0.token.type) }
        guard let tokens = try? marketKit.tokens(queries: tokenQuerys) else { return }
        
        state = .loading
        viewItems.removeAll()
        let allPairs = getAllPair(activeWallets: activeWallets)
        
        Task {
            for pair in allPairs {
                do {
                    let pairItemA = try buildLiquidityPairItem(tokens: tokens, wallet: pair.0)
                    let pairItemB = try buildLiquidityPairItem(tokens: tokens, wallet: pair.1)

                    if let item = await getLiquidityRecordItem(walletA: pair.0, pairItemA: pairItemA, walletB: pair.1, pairItemB: pairItemB) {
                        viewItems.append(item)
                    }
                }catch {
                    state = .failed(error: error.localizedDescription)
                }
            }
            state = .completed(datas: viewItems)
        }
    }

}
extension LiquidityRecordService {
    
    private func getAllPair(activeWallets: [Wallet]) -> [(Wallet,Wallet)] {
        var pairs: [(Wallet, Wallet)] = []
        if activeWallets.count > 0 {
            for i in 0 ..< activeWallets.count - 1 {
                if activeWallets[i].token.blockchainType == activeWallets[i+1].token.blockchainType {
                    pairs.append((activeWallets[i], activeWallets[i+1]))
                }
            }
        }
        return pairs
    }
    
    private func address(token: MarketKit.Token) throws -> EvmKit.Address {
        switch token.type {
        case .native: return try EvmKit.Address(hex: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        case .eip20(let address): return try EvmKit.Address(hex: address)
        default: throw LiquidityRecordError.invalidAddress
        }
    }
            
    private func wethAddressString(chain: BlockchainType) throws -> String {
        switch chain {
        case .ethereum: return "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
        case .optimism: return "0x4200000000000000000000000000000000000006"
        case .binanceSmartChain: return "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
        case .polygon: return "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"
        case .avalanche: return "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
        case .arbitrumOne: return "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
        default: throw UnsupportedChainError.noWethAddress
        }
    }
    
    private var activeWallets: [Wallet] {
        walletManager.activeWallets.filter { $0.token.blockchainType == currentBlockchainType && $0.token.coin.code != codeName }
    }
    
    private var codeName: String {
        switch currentBlockchainType {
        case .binanceSmartChain: return "Cake-LP"
        case .ethereum: return "UNI-V2"
        default: return ""
        }
    }
    
    private func getWallet(token: MarketKit.Token) -> Wallet? {
        activeWallets.filter { $0.token == token }.first
    }
    
    private func getReceiveAddress(wallet: Wallet) -> EvmKit.Address? {
        guard let depositAdapter = adapterManager.depositAdapter(for: wallet) else { return nil }
        return try? EvmKit.Address(hex: depositAdapter.receiveAddress.address)
    }
    
    private func buildLiquidityPairItem(tokens: [MarketKit.Token], wallet: Wallet) throws -> LiquidityPairItem {
        
        if  let token = tokens.first(where: { $0.coin.uid == wallet.coin.uid && $0.blockchainType == wallet.token.blockchainType}) {
            let tokenAddress = try address(token: token)
            return LiquidityPairItem(token: token, address: tokenAddress)
        } else {
            let address = try wethAddressString(chain: wallet.token.blockchainType)
            let tokenAddress = try EvmKit.Address(hex: address)
            return LiquidityPairItem(token: wallet.token, address: tokenAddress)
        }
    }
}

extension LiquidityRecordService {
    
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }
}

extension LiquidityRecordService {
    
    private func liquiditypoolInfo(evmKit: EvmKit.Kit, pairAddress: EvmKit.Address, receiveAddress: EvmKit.Address) async throws -> PoolInfo {
        let (reserve0, reserve1) = try await getReserves(evmKit: evmKit, contractAddress: pairAddress)
        let poolTokenTotalSupply = try await getTotalSupply(evmKit: evmKit, contractAddress: pairAddress)
        let balanceOfAccount = try await getBalanceOf(evmKit: evmKit, contractAddress: pairAddress, walletAddress: receiveAddress)
        print("balanceOfAccount:\(balanceOfAccount.description)")
        return PoolInfo(pooltToken0Amount: reserve0, pooltToken1Amount: reserve1, balanceOfAccount: balanceOfAccount, poolTokenTotalSupply: poolTokenTotalSupply)
    }
}

extension LiquidityRecordService {

    private func getLiquidityRecordItem(walletA: Wallet, pairItemA: LiquidityPairItem, walletB: Wallet, pairItemB: LiquidityPairItem) async -> LiquidityRecordViewModel.RecordItem? {
        guard let receiveAddress = getReceiveAddress(wallet: walletA) else { return nil }
        guard let evmKit = evmKitWrapper?.evmKit else { return nil }
        guard let liquidityPair = LiquidityPair.getPairAddress(evmKit: evmKit, itemA: pairItemA, itemB: pairItemB) else { return nil }
        do {
            let pairAddress = liquidityPair.pairAddress
            let poolInfo = try await liquiditypoolInfo(evmKit: evmKit, pairAddress: pairAddress, receiveAddress: receiveAddress)
            guard poolInfo.balanceOfAccount > 0 else { return nil }
            return LiquidityRecordViewModel.RecordItem(poolInfo: poolInfo, pair: liquidityPair)
        }catch {
            return nil
        }
    }
}

extension LiquidityRecordService {
    
    func removeLiquidity(viewItem: LiquidityRecordViewModel.RecordItem, ratio: BigUInt) {
        state = .loading
        self.ratio = ratio
        Task {
            do {
                guard let wallet = getWallet(token: viewItem.pair.item0.token), let receiveAddress = getReceiveAddress(wallet: wallet) else{ return }
                guard let evmKitWrapper = evmKitWrapper else { return }
                let pairAddress = viewItem.pair.pairAddress
                let poolInfo = try await liquiditypoolInfo(evmKit: evmKitWrapper.evmKit, pairAddress: pairAddress, receiveAddress: receiveAddress)
                let eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKitWrapper.evmKit, contractAddress: pairAddress)
                try await allowance(eip20Kit: eip20Kit, viewItem: viewItem, pairAddress: pairAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
            }catch {
                state = .failed(error: error.localizedDescription)
            }
        }
    }
    
    private func allowance(eip20Kit: Eip20Kit.Kit, viewItem: LiquidityRecordViewModel.RecordItem, pairAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        guard let evmKit = evmKitWrapper?.evmKit else { return }
        let routerAddressString = try Constants.routerAddressString(chain: evmKit.chain)
        let contractAddress = try EvmKit.Address(hex: routerAddressString)
        let result = try await eip20Kit.allowance(spenderAddress: contractAddress, defaultBlockParameter: .latest)
        let liquidity = poolInfo.balanceOfAccount

        guard let decimals = Decimal(bigUInt: liquidity, decimals: 0), decimals > 0 else {return }
        
        if let significand = Decimal(string: result), significand >= decimals {
            remove(viewItem: viewItem, contractAddress: contractAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
        }else {
            try await approve(eip20Kit: eip20Kit, viewItem: viewItem, receiveAddress: receiveAddress, poolInfo: poolInfo)
        }
    }
    
    private func approve(eip20Kit: Eip20Kit.Kit, viewItem: LiquidityRecordViewModel.RecordItem, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        guard let evmKit = evmKitWrapper?.evmKit else { return }
        let routerAddressString = try Constants.routerAddressString(chain: evmKit.chain)
        let contractAddress = try EvmKit.Address(hex: routerAddressString)
        let maxValue = BigUInt(Data(hex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
        let transactionData = eip20Kit.approveTransactionData(spenderAddress: contractAddress, amount: maxValue)
        try await send(transactionData: transactionData)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] fullTransaction in
                self?.remove(viewItem: viewItem, contractAddress: contractAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
            }, onError: { error in
                self.state = .approveFailed
            })
            .disposed(by: disposeBag)
    }
    
    private func remove(viewItem: LiquidityRecordViewModel.RecordItem, contractAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) {
        let addressA = viewItem.pair.item0.address
        let addressB = viewItem.pair.item1.address
        let slippage:(BigUInt, BigUInt) = (5, 1000)
        let amountAMin = (viewItem.poolInfo.userToken0Amount * slippage.0 / slippage.1) * ratio / 100
        let amountBMin = (viewItem.poolInfo.userToken1Amount * slippage.0 / slippage.1) * ratio / 100
        
        let deadline = Constants.getDeadLine()
        
        let liquidity = poolInfo.balanceOfAccount * ratio / 100
        
        let method = RemoveLiquidityMethod(tokenA: addressA, tokenB: addressB, liquidity: liquidity, amountAMin: amountAMin, amountBMin: amountBMin, to: receiveAddress, deadline: deadline)
        let transactionData = EvmKit.TransactionData(to: contractAddress, value: 0, input: method.encodedABI())
        Task {
            do {
                try await send(transactionData: transactionData)
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe(onSuccess: { [weak self] fullTransaction in
                        if  let strongSelf = self {
                            if let index = strongSelf.viewItems.firstIndex(where: { $0.pair.pairAddress ==  viewItem.pair.pairAddress }) {
                                strongSelf.viewItems.remove(at: index)
                                strongSelf.state = .removeSuccess
                            }
                        }

                    }, onError: { error in
                        let message = self.errorMessage(error: error, item: viewItem)
                        self.state = .removeFailed(error: message)
                    })
                    .disposed(by: disposeBag)
            } catch {
                let message = self.errorMessage(error: error, item: viewItem)
                self.state = .removeFailed(error: message)
            }
        }
    }
    
    private func send(transactionData: TransactionData) async throws -> Single<FullTransaction> {
        guard let evmKitWrapper = evmKitWrapper else { return Single.error( LiquidityRecordError.evmKitWrapperError) }
        let nonce = try await evmKitWrapper.evmKit.nonce(defaultBlockParameter: .pending)
        guard let gasPrice = legacyGasPrice else { return Single.error( LiquidityRecordError.noGasPrice) }
        let gasLimit = try await evmKitWrapper.evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)
    
        return evmKitWrapper.sendSingle(
                        transactionData: transactionData,
                        gasPrice: gasPrice,
                        gasLimit: gasLimit,
                        nonce: nonce
                )
    }
        
    private func syncgasPrice(evmKitWrapper: EvmKitWrapper) {
        let gasPriceProvider = LegacyGasPriceProvider(evmKit: evmKitWrapper.evmKit)
        gasPriceProvider.gasPriceSingle()
            .subscribe(
                onSuccess: { [weak self] gasPrice in
                    self?.legacyGasPrice =  gasPrice
                },
                onError: { [weak self] error in
                    self?.state = .gasPriceFailed
                }
            )
            .disposed(by: disposeBag)
    }
    
    func errorMessage(error: Error, item: LiquidityRecordViewModel.RecordItem) -> String {
        if case JsonRpcResponse.ResponseError.rpcError(_) = error {
            let feeType: String
            switch item.tokenA.blockchainType {
            case .binanceSmartChain:
                feeType = "BNB"
            case .ethereum:
                feeType = "ETH"
            default:
                feeType = ""
            }
            return "liquidity.remove.error.insufficient".localized(feeType)
        }
        return error.localizedDescription
    }
    
}

extension LiquidityRecordService {
    
    private func getNonces(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address, receiveAddress: EvmKit.Address) async throws -> BigUInt {
        
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetNoncesMethod(address: receiveAddress).encodedABI())
        var rawReserve: BigUInt = 0
        if data.count == 32 {
            rawReserve = BigUInt(data[0...31])
        }
        return rawReserve
    }
    
    private func getTotalSupply(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> BigUInt {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetTotalSupplyMethod().encodedABI())
        var rawReserve: BigUInt = 0
        if data.count >= 32 {
            rawReserve = BigUInt(data[0...31])
        }
        return rawReserve
    }
    
    private func getReserves(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> (BigUInt,BigUInt) {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetReservesMethod().encodedABI())
        var rawReserve0: BigUInt = 0
        var rawReserve1: BigUInt = 0
        if data.count == 3 * 32 {
            rawReserve0 = BigUInt(data[0...31])
            rawReserve1 = BigUInt(data[32...63])
        }
        return (rawReserve0,rawReserve1)
    }
    
    private func getBalanceOf(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address, walletAddress: EvmKit.Address) async throws -> BigUInt {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetBalanceOfMethod(address: walletAddress).encodedABI())
        var rawReserve: BigUInt = 0
        if data.count >= 32 {
            rawReserve = BigUInt(data[0...31])
        }
        return rawReserve
    }    
}

extension LiquidityRecordService {
    
    struct PoolInfo {
        let pooltToken0Amount: BigUInt
        let pooltToken1Amount: BigUInt
        let balanceOfAccount: BigUInt
        let poolTokenTotalSupply: BigUInt
        
        var shareRate: Decimal {
            (Decimal(bigUInt: balanceOfAccount, decimals: 0) ?? 0) / (Decimal(bigUInt: poolTokenTotalSupply, decimals: 0) ?? 1)
        }
        
        var userToken0Amount: BigUInt {
            pooltToken0Amount * balanceOfAccount / poolTokenTotalSupply
        }
        
        var userToken1Amount: BigUInt {
            pooltToken1Amount * balanceOfAccount / poolTokenTotalSupply
        }
    }
    
    enum RemoveType {
        case all
        case ratio(value: BigUInt)
    }
    
    
    public enum UnsupportedChainError: Error {
        case noWethAddress
    }
    
    enum LiquidityRecordError: Error {
        case invalidAddress
        case insufficientAmount
        case unsupportedToken
        case dataError
        case evmKitWrapperError
        case noGasPrice
    }
    
    enum LiquidityABIError: Error {
        case getNameError
        case getNoncesError
        case getTotalSupplyError
        case getReservesError
        case getBalanceOfError
    }
    
    enum State {
        case loading
        case completed(datas: [LiquidityRecordViewModel.RecordItem])
        case failed(error: String)
        case approveFailed
        case removeSuccess
        case gasPriceFailed
        case removeFailed(error: String)
    }
}

