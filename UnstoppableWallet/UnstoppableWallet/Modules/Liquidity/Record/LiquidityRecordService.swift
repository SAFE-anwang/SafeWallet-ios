import Foundation
import RxSwift
import RxRelay
import MarketKit
import CurrencyKit
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
    private let marketKit: MarketKit.Kit
    private let walletManager: WalletManager
    private let adapterManager: AdapterManager
    private let evmKitWrapper: EvmKitWrapper
    private let evmKit: EvmKit.Kit
    private let swapKit: UniswapKit.Kit
    private var viewItemsRelay = BehaviorRelay<[LiquidityRecordViewModel.RecordItem]>(value: [])
    private var viewItems = [LiquidityRecordViewModel.RecordItem]()
    private let disposeBag = DisposeBag()
    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "io.horizontalsystems.unstoppable.liquidity_record")

    
    init(marketKit: MarketKit.Kit, walletManager: WalletManager, adapterManager: AdapterManager, evmKitWrapper: EvmKitWrapper, swapKit: UniswapKit.Kit) {
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.adapterManager = adapterManager
        self.evmKitWrapper = evmKitWrapper
        self.evmKit = evmKitWrapper.evmKit
        self.swapKit = swapKit        
    }
    
    func refresh() {
        syncItems()
    }
    
    private func syncItems() {
        
        let tokenQuerys = activeWallets.compactMap { TokenQuery(blockchainType: .binanceSmartChain, tokenType: $0.token.type) }
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
                    state = .failed(error: LiquidityRecordError.dataError)
                }
            }
            state = .completed(data: viewItems)
        }
    }

}
extension LiquidityRecordService {
    
    private func getAllPair(activeWallets: [Wallet]) -> [(Wallet,Wallet)] {
        var pairs: [(Wallet, Wallet)] = []
        for i in 0 ..< activeWallets.count - 1 {
            pairs.append((activeWallets[i], activeWallets[i+1]))
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
        walletManager.activeWallets.filter { $0.token.blockchainType == .binanceSmartChain && $0.token.coin.code != "Cake-LP" }
    }
    
    private func getWallet(token: MarketKit.Token) -> Wallet? {
        activeWallets.filter { $0.token == token }.first
    }
    
    private func getReceiveAddress(wallet: Wallet) -> EvmKit.Address? {
        guard let depositAdapter = adapterManager.depositAdapter(for: wallet) else { return nil }
        return try? EvmKit.Address(hex: depositAdapter.receiveAddress.address)
    }
    
    private func buildLiquidityPairItem(tokens: [MarketKit.Token], wallet: Wallet) throws -> LiquidityPairItem {
        
        if  let token = tokens.first(where: { $0.coin.uid == wallet.coin.uid }) {
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

typealias PoolInfo = (balanceOfAccount: BigUInt, reserves: (BigUInt,BigUInt) , poolTokenTotalSupply: BigUInt)

extension LiquidityRecordService {
    
    private func liquiditypoolInfo(pairAddress: EvmKit.Address, receiveAddress: EvmKit.Address) async throws -> PoolInfo {
        let balanceOfAccount = try await getBalanceOf(contractAddress: pairAddress, walletAddress: receiveAddress)
        let (reserve0, reserve1) = try await getReserves(contractAddress: pairAddress)
        let poolTokenTotalSupply = try await getTotalSupply(contractAddress: pairAddress)
        return PoolInfo(balanceOfAccount, (reserve0, reserve1), poolTokenTotalSupply)
    }
}

extension LiquidityRecordService {

    private func getLiquidityRecordItem(walletA: Wallet, pairItemA: LiquidityPairItem, walletB: Wallet, pairItemB: LiquidityPairItem) async -> LiquidityRecordViewModel.RecordItem? {
        
        guard let receiveAddress = getReceiveAddress(wallet: walletA) else { return nil }
        let liquidityPair = LiquidityPair.getPairAddress(itemA: pairItemA, itemB: pairItemB)
        let tokenA = liquidityPair.item0.token
        let tokenB = liquidityPair.item1.token
        let pairAddress = liquidityPair.pairAddress
        
        do {
            let poolInfo = try await liquiditypoolInfo(pairAddress: pairAddress, receiveAddress: receiveAddress)
            guard poolInfo.balanceOfAccount > 0 else { return nil }

            let shareRate = (Decimal(bigUInt: poolInfo.balanceOfAccount, decimals: 0) ?? 0) / (Decimal(bigUInt: poolInfo.poolTokenTotalSupply, decimals: 0) ?? 0)
            let decimalValueA = (Decimal(bigUInt: poolInfo.reserves.0, decimals: tokenA.decimals) ?? 0) * shareRate
            let decimalValueB = (Decimal(bigUInt: poolInfo.reserves.1, decimals: tokenB.decimals) ?? 0) * shareRate
            let liquidity = Decimal(bigUInt: poolInfo.balanceOfAccount, decimals: 18) ?? 0
            let totalSupply = Decimal(bigUInt: poolInfo.poolTokenTotalSupply, decimals: 16) ?? 0
            
            return LiquidityRecordViewModel.RecordItem(tokenA: tokenA,
                                                       tokenB: tokenB,
                                                       amountA: decimalValueA,
                                                       amountB: decimalValueB,
                                                       liquidity: liquidity,
                                                       shareRate: shareRate,
                                                       totalSupply: totalSupply,
                                                       pair: liquidityPair)
        }catch {
            return nil
        }
    }
}

extension LiquidityRecordService {
    
    func removeLiquidity(viewItem: LiquidityRecordViewModel.RecordItem) {
        state = .loading
        Task {
            do {
                guard let wallet = getWallet(token: viewItem.pair.item0.token), let receiveAddress = getReceiveAddress(wallet: wallet) else{ return }
                let pairAddress = viewItem.pair.pairAddress
                let poolInfo = try await liquiditypoolInfo(pairAddress: pairAddress, receiveAddress: receiveAddress)
                let eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: pairAddress)
                try await allowance(eip20Kit: eip20Kit, viewItem: viewItem, pairAddress: pairAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
            }catch {
                state = .failed(error: LiquidityRecordError.dataError)
            }
        }
    }
    
    private func allowance(eip20Kit: Eip20Kit.Kit, viewItem: LiquidityRecordViewModel.RecordItem, pairAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        let contractAddress = try EvmKit.Address(hex: Constants.DEX.PANCAKE_V2_ROUTER_ADDRESS)
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
        let contractAddress = try EvmKit.Address(hex: Constants.DEX.PANCAKE_V2_ROUTER_ADDRESS)
//        let liquidity = poolInfo.balanceOfAccount
        let maxValue = BigUInt(Data(hex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
        let transactionData = eip20Kit.approveTransactionData(spenderAddress: contractAddress, amount: maxValue)
        try await send(transactionData: transactionData)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] fullTransaction in
                self?.remove(viewItem: viewItem, contractAddress: contractAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
            }, onError: { error in
                self.state = .failed(error: error)
            })
            .disposed(by: disposeBag)
    }
    
    private func remove(viewItem: LiquidityRecordViewModel.RecordItem, contractAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) {
        let shareRate = (Decimal(bigUInt: poolInfo.balanceOfAccount, decimals: 0) ?? 0) / (Decimal(bigUInt: poolInfo.poolTokenTotalSupply, decimals: 0) ?? 0)
        let addressA = viewItem.pair.item0.address
        let addressB = viewItem.pair.item1.address

        let decimalAMin = (Decimal(bigUInt: poolInfo.reserves.0, decimals: 0) ?? 0) * shareRate * Constants.slippage
        let decimalBMin = (Decimal(bigUInt: poolInfo.reserves.1, decimals: 0) ?? 0) * shareRate * Constants.slippage
        let amountAMin = BigUInt(decimalAMin.hs.roundedString(decimal: 0)) ?? 0
        let amountBMin = BigUInt(decimalBMin.hs.roundedString(decimal: 0)) ?? 0

        let deadline = Constants.getDeadLine()
        
        let liquidity = poolInfo.balanceOfAccount

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
                                strongSelf.state = .removeSuccess(data: strongSelf.viewItems)
                            }
                        }

                    }, onError: { error in
                        self.state = .failed(error: error)
                    })
                    .disposed(by: disposeBag)
            } catch {
                state = .failed(error: LiquidityRecordError.dataError)
            }
        }

    }
    
    private func send(transactionData: TransactionData) async throws -> Single<FullTransaction> {
        
        let nonce = try await evmKit.nonce(defaultBlockParameter: .pending)
        let gasPrice = GasPrice.legacy(gasPrice: FeePriceScale.gwei.scaleValue * 5)
        let gasLimit = 500000
        return evmKitWrapper.sendSingle(
                        transactionData: transactionData,
                        gasPrice: gasPrice,
                        gasLimit: gasLimit,
                        nonce: nonce
                )
    }
    
}

extension LiquidityRecordService {
    
    private func getNonces(contractAddress: EvmKit.Address, receiveAddress: EvmKit.Address) async throws -> BigUInt {
        
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetNoncesMethod(address: receiveAddress).encodedABI())
        var rawReserve: BigUInt = 0
        if data.count == 32 {
            rawReserve = BigUInt(data[0...31])
        }
        return rawReserve
    }
    
    private func getTotalSupply(contractAddress: EvmKit.Address) async throws -> BigUInt {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetTotalSupplyMethod().encodedABI())
        var rawReserve: BigUInt = 0
        if data.count >= 32 {
            rawReserve = BigUInt(data[0...31])
        }
        return rawReserve
    }
    
    private func getReserves(contractAddress: EvmKit.Address) async throws -> (BigUInt,BigUInt) {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetReservesMethod().encodedABI())
        var rawReserve0: BigUInt = 0
        var rawReserve1: BigUInt = 0
        if data.count == 3 * 32 {
            rawReserve0 = BigUInt(data[0...31])
            rawReserve1 = BigUInt(data[32...63])
        }
        return (rawReserve0,rawReserve1)
    }
    
    private func getBalanceOf(contractAddress: EvmKit.Address, walletAddress: EvmKit.Address) async throws -> BigUInt {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetBalanceOfMethod(address: walletAddress).encodedABI())
        var rawReserve: BigUInt = 0
        if data.count >= 32 {
            rawReserve = BigUInt(data[0...31])
        }
        return rawReserve
    }    
}
extension LiquidityRecordService {
        
    public enum UnsupportedChainError: Error {
        case noWethAddress
    }
    
    enum LiquidityRecordError: Error {
        case invalidAddress
        case insufficientAmount
        case unsupportedToken
        case dataError
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
        case completed(data: [LiquidityRecordViewModel.RecordItem])
        case removeSuccess(data: [LiquidityRecordViewModel.RecordItem])
        case failed(error: Error)
    }
}

