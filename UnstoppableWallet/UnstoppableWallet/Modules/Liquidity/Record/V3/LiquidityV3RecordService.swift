import Foundation
import CryptoKit
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
import HsToolKit

class LiquidityV3RecordService {
    private let blockchainType: BlockchainType
    private let marketKit: MarketKit.Kit
    private let walletManager: WalletManager
    private let adapterManager: AdapterManager

    private let disposeBag = DisposeBag()
    private let stateRelay = PublishRelay<State>()
    
    private var legacyGasPrice: GasPrice?
    private let evmKitWrapper: EvmKitWrapper
    private let uniswapKit: UniswapKit.KitV3
    private let rpcSource: RpcSource
    private let gasPriceProvider: LegacyGasPriceProvider
    
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private var activeWallets: [Wallet] {
        walletManager.activeWallets.filter { $0.token.blockchainType == blockchainType }
    }

    init?(dexType: DexType, marketKit: MarketKit.Kit, walletManager: WalletManager, adapterManager: AdapterManager, blockchainType: BlockchainType) {
        
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else { return nil }
        guard let rpcSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: blockchainType)?.rpcSource else { return nil }
        let uniswapKit = try! UniswapKit.KitV3.instance(dexType: dexType)
        let gasPriceProvider = LegacyGasPriceProvider(evmKit: evmKitWrapper.evmKit)
        
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.adapterManager = adapterManager
        self.blockchainType = blockchainType
        
        self.evmKitWrapper = evmKitWrapper
        self.uniswapKit = uniswapKit
        self.rpcSource = rpcSource
        self.gasPriceProvider = gasPriceProvider
        syncgasPrice()
        
        liquidityV3Records()
    }
    
    func refresh() {
        liquidityV3Records()
    }
    
    private func liquidityV3Records() {
        Task {
            do {
                let chain = evmKitWrapper.evmKit.chain
                let owner = evmKitWrapper.evmKit.receiveAddress
                let tokenQuerys = activeWallets.compactMap { TokenQuery(blockchainType: $0.token.blockchainType, tokenType: $0.token.type) }
                guard let tokens = try? marketKit.tokens(queries: tokenQuerys) else { return }
                let datas = try await uniswapKit.ownedLiquidity(rpcSource: rpcSource, chain: chain, owner: owner)
                let ownedDatas = datas.filter{$0.liquidity > 0}
                var items = [LiquidityV3RecordViewModel.V3RecordItem]()
                for positions in ownedDatas {
                    if let item = try await viewItem(tokens: tokens, positions: positions) {
                        items.append(item)
                    }
                }
                state = .completed(datas: items)
            }catch {
                state = .failed(error: error.localizedDescription)
            }
        }
    }
    
    func getAmountsForLiquidity(item: LiquidityV3RecordViewModel.V3RecordItem, liquidity: BigUInt) async throws -> (String?, String?) {
        let chain = evmKitWrapper.evmKit.chain
        let (amount0, amount1, _) = try await uniswapKit.getAmountsForLiquidity(positions: item.positions, rpcSource: rpcSource, chain: chain, liquidity: liquidity)
        
        let amount0Formatted = Decimal(bigUInt: amount0, decimals: item.token0.decimals)?.formattedAmount
        let amount1Formatted = Decimal(bigUInt: amount1, decimals: item.token1.decimals)?.formattedAmount
        return (amount0Formatted, amount1Formatted)
    }
}

extension LiquidityV3RecordService {
    
    func removeLiquidity(item: LiquidityV3RecordViewModel.V3RecordItem, ratio: BigUInt) {
        
        let chain = evmKitWrapper.evmKit.chain
        let recipient = evmKitWrapper.evmKit.receiveAddress
        let liquidity = item.positions.liquidity * ratio / 100
        let slippage = slippage(positions: item.positions)
        let deadline = deadLine()
        Task {
            do {
                try await allowance(item: item)
                
                let transactionData = try await uniswapKit.removeLiquidityTransactionData(positions: item.positions, rpcSource: rpcSource, chain: chain, liquidity: liquidity, slippage: slippage, recipient: recipient, deadline: deadline)
                
                try await send(transactionData: transactionData)
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe(onSuccess: { [weak self] _ in
                        self?.state = .removeSuccess

                    }, onError: { error in
                        let message = self.errorMessage(error: error, item: item)
                        self.state = .removeFailed(error: message)
                    })
                    .disposed(by: disposeBag)
            }catch {
                state = .failed(error: error.localizedDescription)
            }
        }
    }
    
    private func allowance(item: LiquidityV3RecordViewModel.V3RecordItem) async throws  {
        
        let evmKit = evmKitWrapper.evmKit
        let chain = evmKitWrapper.evmKit.chain
        
        let token0Address = item.positions.token0
        let token1Address = item.positions.token1
        let eip20Kit0 = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: token0Address)
        let eip20Kit1 = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: token1Address)
        
        let spenderAddress = uniswapKit.nonfungiblePositionAddress(chain: evmKit.chain)
        let result0 = try await eip20Kit0.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)
        let result1 = try await eip20Kit1.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)
        
        let (amount0, amount1, _) = try await uniswapKit.getAmountsForLiquidity(positions: item.positions, rpcSource: rpcSource, chain: chain, liquidity: item.positions.liquidity)
        
        let allowance0 = BigUInt(result0) ?? 0
        let allowance1 = BigUInt(result1) ?? 0
        
        if  allowance0 < amount0  {
            try await approve(tokenAddress: token0Address)
        }
        
        if allowance1 < amount1  {
            try await approve(tokenAddress: token1Address)
        }
    }
    
    private func approve(tokenAddress: EvmKit.Address) async throws {
        let evmKit = evmKitWrapper.evmKit

        guard let gasPrice = legacyGasPrice else { throw LiquidityV3RecordError.noGasPrice }
        let nonce = try await evmKitWrapper.evmKit.nonce(defaultBlockParameter: .pending)
        let eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: tokenAddress)
        
        let spenderAddress = uniswapKit.nonfungiblePositionAddress(chain: evmKit.chain)
        let maxValue = BigUInt(Data(hex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
        let transactionData = eip20Kit.approveTransactionData(spenderAddress: spenderAddress, amount:maxValue)
        
        let gasLimit = try await evmKitWrapper.evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)
        let _ = try await evmKitWrapper.send(transactionData: transactionData, gasPrice: gasPrice, gasLimit: gasLimit, nonce: nonce)
    }
    
    private func send(transactionData: TransactionData) async throws -> Single<FullTransaction> {
        
        guard let gasPrice = legacyGasPrice else { return Single.error( LiquidityV3RecordError.noGasPrice) }
        let nonce = try await evmKitWrapper.evmKit.nonce(defaultBlockParameter: .pending)
        let gasLimit = try await evmKitWrapper.evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)// 500000
    
        return evmKitWrapper.sendSingle(
                        transactionData: transactionData,
                        gasPrice: gasPrice,
                        gasLimit: gasLimit,
                        nonce: nonce
        )
    }
}

private extension LiquidityV3RecordService {

    func viewItem(tokens: [MarketKit.Token], positions: Positions) async throws -> LiquidityV3RecordViewModel.V3RecordItem? {
        let chain = evmKitWrapper.evmKit.chain
        let (amount0, amount1, isInRange) = try await uniswapKit.getAmountsForLiquidity(positions: positions, rpcSource: rpcSource, chain: chain, liquidity: positions.liquidity)
        guard let token0 = marketToken(tokens: tokens, tokenAddress: positions.token0) else { return nil }
        guard let token1 = marketToken(tokens: tokens, tokenAddress: positions.token1) else { return nil }
        let t0 = try uniswapToken(token: token0)
        let t1 = try uniswapToken(token: token1)

        let lowerPrice = try tickToPrice(tick: positions.tickLower, token0: t0, token1: t1)
        let upperPrice = try tickToPrice(tick: positions.tickUpper, token0: t0, token1: t1)

        return LiquidityV3RecordViewModel.V3RecordItem(positions: positions,
                                              token0: token0,
                                              token1: token1,
                                              isInRange: isInRange,
                                              token0Amount: amount0,
                                              token1Amount: amount1,
                                              lowerPrice: lowerPrice,
                                              upperPrice: upperPrice
        )

    }
        

    func tickToPrice(tick: BigInt, token0: UniswapKit.Token, token1: UniswapKit.Token) throws -> Decimal? {
        let sqrtPriceX96 = try uniswapKit.getSqrtRatioAtTick(tick: tick)
        let price = uniswapKit.correctedX96Price(sqrtPriceX96: sqrtPriceX96, tokenIn: token0, tokenOut: token1)
        return price
    }

        
    func syncgasPrice() {
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
    
    func marketToken(tokens: [MarketKit.Token], tokenAddress: EvmKit.Address) -> MarketKit.Token? {
        return tokens.first { token in
            do {
                let uniswapToken = try uniswapToken(token: token)
                return uniswapToken.address == tokenAddress
            }catch {return false }
        }
    }
    
    func uniswapToken(token: MarketKit.Token) throws -> UniswapKit.Token {
        let evmKit = evmKitWrapper.evmKit
        switch token.type {
        case .native: return try uniswapKit.etherToken(chain: evmKit.chain)
        case let .eip20(address): return try uniswapKit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw TokenError.unsupportedToken
        }
    }
    
    func errorMessage(error: Error, item: LiquidityV3RecordViewModel.V3RecordItem) -> String {
        if case JsonRpcResponse.ResponseError.rpcError(_) = error {
            let feeType: String
            switch item.token0.blockchainType {
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

extension LiquidityV3RecordService {
    
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }
}

extension LiquidityV3RecordService {

    func slippage(positions: Positions) -> BigUInt {
        (positions.token0.hex == "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c" || positions.token1.hex == "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c") ? 2500 : 500
    }
    
    func deadLine() -> BigUInt {
        let deadLine: Int = 20 // 20 min
        let txDeadLine = (UInt64(Date().timeIntervalSince1970) + UInt64(60 * deadLine))
        return BigUInt(integerLiteral: txDeadLine)
    }
}

extension LiquidityV3RecordService {
    
    enum LiquidityV3RecordError: Error {
        case invalidAddress
        case insufficientAmount
        case unsupportedToken
        case dataError
        case evmKitWrapperError
        case noGasPrice
    }

    enum State {
        case loading
        case completed(datas: [LiquidityV3RecordViewModel.V3RecordItem])
        case failed(error: String)
        case approveFailed
        case removeSuccess
        case gasPriceFailed
        case removeFailed(error: String)
    }
    
    enum TokenError: Error {
        case unsupportedToken
    }

}

/*
private extension LiquidityV3RecordService {
    
    struct EIP712TypedData {
        let domainSeparator: Data
        let permitTypehash: Data
        
        let tokenId: BigUInt
        let liquidity: BigUInt
        let amount0Min: BigUInt
        let amount1Min: BigUInt
        let deadline: BigUInt
        
        func message() -> Data {
            var message = Data()
            message.append(permitTypehash)
            message.append(Data(from: tokenId))
            message.append(Data(from: liquidity))
            message.append(Data(from: amount0Min))
            message.append(Data(from: amount1Min))
            message.append(Data(from: deadline))
            
            return Crypto.sha3(Data([UInt8(0x19), UInt8(0x01)]) + domainSeparator + Crypto.sha3(message))
        }
    }

    struct SelfPermitEIP712TypedData {
        let domainSeparator: Data
        
        let from: EvmKit.Address
        let to: EvmKit.Address
        let amount: BigUInt
        
        func message() -> Data {
            var message = Data()
            message.append(from.raw)
            message.append(to.raw)
            message.append(Data(from: amount))
            return Crypto.sha3(Data([UInt8(0x19), UInt8(0x01)]) + domainSeparator + Crypto.sha3(message))
        }
    }
}
*/
