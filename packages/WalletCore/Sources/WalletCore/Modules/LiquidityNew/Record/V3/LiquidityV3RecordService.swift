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

    private let disposeBag = DisposeBag()
    private let stateRelay = PublishRelay<State>()

    private var legacyGasPrice: GasPrice?
    private var selectedGasPrice: GasPrice?
    private var nextNonceOverride: Int?
    private var feePlan: LiquidityFeePlan?
    private var plannedRatio: BigUInt?
    private var plannedGasPrice: GasPrice?
    private(set) var lastSubmittedTransactionHash: String?
    private let evmKitWrapper: EvmKitWrapper
    private let uniswapKit: UniswapKit.KitV3
    private let rpcSource: RpcSource
    private let gasPriceProvider: LegacyGasPriceProvider
    private var ratio: BigUInt = 100
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }

    init?(dexType: DexType, marketKit: MarketKit.Kit, walletManager _: WalletManager, adapterManager _: AdapterManager, blockchainType: BlockchainType) {

        guard let evmKitWrapper = ChildWalletBridge.shared.activeEvmKitWrapper(blockchainType: blockchainType) else { return nil }

        guard let rpcSource = Core.shared.evmSyncSourceManager.httpSyncSource(blockchainType: blockchainType)?.rpcSource else { return nil }

        let uniswapKit = try! UniswapKit.KitV3.instance(dexType: dexType)
        let gasPriceProvider = LegacyGasPriceProvider(evmKit: evmKitWrapper.evmKit)

        self.marketKit = marketKit
        self.blockchainType = blockchainType

        self.evmKitWrapper = evmKitWrapper
        self.uniswapKit = uniswapKit
        self.rpcSource = rpcSource
        self.gasPriceProvider = gasPriceProvider
        syncgasPrice()

    }

    func refresh() {
        refreshTask?.cancel()
        refreshGeneration += 1
        liquidityV3Records()
    }

    private func liquidityV3Records() {
        let generation = refreshGeneration
        state = .loading
        refreshTask = Task { [weak self] in
            do {
                guard let self else { return }
                let chain = self.evmKitWrapper.evmKit.chain
                let owner = self.evmKitWrapper.evmKit.receiveAddress
                let datas = try await self.uniswapKit.ownedLiquidity(rpcSource: self.rpcSource, chain: chain, owner: owner)
                let ownedDatas = datas.filter{$0.liquidity > 0}
                let tokens = try self.fetchTokens(for: ownedDatas)
                var items = [LiquidityV3RecordViewModel.V3RecordItem]()
                for positions in ownedDatas {
                    try Task.checkCancellation()
                    if let item = try await self.viewItem(tokens: tokens, positions: positions) {
                        items.append(item)
                    }
                }
                guard !Task.isCancelled, generation == self.refreshGeneration else { return }
                self.state = .completed(datas: items)
            } catch {
                guard !Task.isCancelled, generation == self?.refreshGeneration else { return }
                self?.state = .failed(error: error.localizedDescription)
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    private func fetchTokens(for positions: [Positions]) throws -> [MarketKit.Token] {
        var queries = [TokenQuery]()
        var seen = Set<String>()

        for position in positions {
            let token0Address = position.token0.hex.lowercased()
            if seen.insert(token0Address).inserted {
                queries.append(TokenQuery(blockchainType: blockchainType, tokenType: .eip20(address: token0Address)))
            }

            let token1Address = position.token1.hex.lowercased()
            if seen.insert(token1Address).inserted {
                queries.append(TokenQuery(blockchainType: blockchainType, tokenType: .eip20(address: token1Address)))
            }
        }

        if queries.isEmpty {
            return []
        }

        return try marketKit.tokens(queries: queries)
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

    func estimateRemoveFee(item: LiquidityV3RecordViewModel.V3RecordItem, ratio: BigUInt, transactionSettings: TransactionSettings?) async throws -> (EvmFeeData, GasPrice) {
        let positionManager = uniswapKit.nonfungiblePositionAddress(chain: evmKitWrapper.evmKit.chain)
        guard !hasPendingRemovalTransaction(positionManager: positionManager) else {
            throw LiquidityV3RecordError.pendingRemoval
        }
        let gasPrice = transactionSettings?.gasPriceData?.userDefined ?? legacyGasPrice
        guard let gasPrice else { throw LiquidityV3RecordError.noGasPrice }
        let gasData = GasPriceData(recommended: gasPrice, userDefined: gasPrice)
        feePlan = nil
        plannedRatio = nil
        plannedGasPrice = nil

        let liquidity = item.positions.liquidity * ratio / 100
        let removeData = try await uniswapKit.removeLiquidityTransactionData(
            positions: item.positions,
            rpcSource: rpcSource,
            chain: evmKitWrapper.evmKit.chain,
            liquidity: liquidity,
            slippage: slippage(positions: item.positions),
            recipient: evmKitWrapper.evmKit.receiveAddress,
            deadline: deadLine()
        )

        let spenderAddress = uniswapKit.nonfungiblePositionAddress(chain: evmKitWrapper.evmKit.chain)
        let eip20Kit0 = try Eip20Kit.Kit.instance(evmKit: evmKitWrapper.evmKit, contractAddress: item.positions.token0)
        let eip20Kit1 = try Eip20Kit.Kit.instance(evmKit: evmKitWrapper.evmKit, contractAddress: item.positions.token1)
        async let allowanceString0 = eip20Kit0.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)
        async let allowanceString1 = eip20Kit1.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)
        async let amounts = uniswapKit.getAmountsForLiquidity(positions: item.positions, rpcSource: rpcSource, chain: evmKitWrapper.evmKit.chain, liquidity: liquidity)
        let (rawAllowance0, rawAllowance1, (amount0, amount1, _)) = try await (allowanceString0, allowanceString1, amounts)
        let allowance0 = BigUInt(rawAllowance0) ?? 0
        let allowance1 = BigUInt(rawAllowance1) ?? 0
        let maxValue = BigUInt(Data(hex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
        var steps = [LiquidityFeeStep]()

        if allowance0 < amount0 {
            let data = eip20Kit0.approveTransactionData(spenderAddress: spenderAddress, amount: maxValue)
            steps.append(try await feeStep(id: "approveToken0", transactionData: data, gasPriceData: gasData))
        }
        if allowance1 < amount1 {
            let data = eip20Kit1.approveTransactionData(spenderAddress: spenderAddress, amount: maxValue)
            steps.append(try await feeStep(id: "approveToken1", transactionData: data, gasPriceData: gasData))
        }

        let requiresApproval = allowance0 < amount0 || allowance1 < amount1
        steps.append(try await feeStep(id: "remove", transactionData: removeData, gasPriceData: gasData, allowFallback: requiresApproval))
        let plan = LiquidityFeePlan(steps: steps)
        feePlan = plan
        plannedRatio = ratio
        plannedGasPrice = gasPrice
        selectedGasPrice = gasPrice
        return (plan.aggregateFeeData, gasPrice)
    }

    private func feeStep(id: String, transactionData: TransactionData, gasPriceData: GasPriceData, allowFallback: Bool = false) async throws -> LiquidityFeeStep {
        do {
            let feeData = try await EvmFeeEstimator().estimateFee(evmKitWrapper: evmKitWrapper, transactionData: transactionData, gasPriceData: gasPriceData, allowFallbackEstimate: false)
            return LiquidityFeeStep(id: id, transactionData: transactionData, gasLimit: feeData.gasLimit, surchargedGasLimit: feeData.surchargedGasLimit, l1Fee: feeData.l1Fee, gasPrice: gasPriceData.userDefined, isFallbackEstimate: false)
        } catch {
            guard allowFallback else { throw error }
            let feeData = try await EvmFeeEstimator().estimateFee(evmKitWrapper: evmKitWrapper, transactionData: transactionData, gasPriceData: gasPriceData, predefinedGasLimit: 500_000, allowFallbackEstimate: false)
            return LiquidityFeeStep(id: id, transactionData: transactionData, gasLimit: feeData.gasLimit, surchargedGasLimit: feeData.surchargedGasLimit, l1Fee: feeData.l1Fee, gasPrice: gasPriceData.userDefined, isFallbackEstimate: true)
        }
    }

    private func matchingFeePlan(for ratio: BigUInt) -> LiquidityFeePlan? {
        guard let feePlan, plannedRatio == ratio,
              let gasPrice = selectedGasPrice ?? legacyGasPrice,
              plannedGasPrice == gasPrice else { return nil }
        return feePlan
    }

    func removeLiquidity(item: LiquidityV3RecordViewModel.V3RecordItem, ratio: BigUInt, transactionSettings: TransactionSettings? = nil) {

        let chain = evmKitWrapper.evmKit.chain
        let recipient = evmKitWrapper.evmKit.receiveAddress
        let liquidity = item.positions.liquidity * ratio / 100
        let slippage = slippage(positions: item.positions)
        let deadline = deadLine()
        selectedGasPrice = transactionSettings?.gasPriceData?.userDefined
        nextNonceOverride = transactionSettings?.nonce
        self.ratio = ratio
        lastSubmittedTransactionHash = nil
        Task {
            do {
                guard !self.hasPendingRemovalTransaction(positionManager: self.uniswapKit.nonfungiblePositionAddress(chain: self.evmKitWrapper.evmKit.chain)) else {
                    throw LiquidityV3RecordError.pendingRemoval
                }
                if let plan = matchingFeePlan(for: ratio) {
                    if plan.step(id: "approveToken0") != nil {
                        try await approve(tokenAddress: item.positions.token0, stepId: "approveToken0", transactionDataOverride: plan.step(id: "approveToken0")?.transactionData)
                    }
                    if plan.step(id: "approveToken1") != nil {
                        try await approve(tokenAddress: item.positions.token1, stepId: "approveToken1", transactionDataOverride: plan.step(id: "approveToken1")?.transactionData)
                    }
                } else {
                    try await allowance(item: item, ratio: ratio)
                }

                let transactionData: TransactionData
                if let planned = matchingFeePlan(for: ratio)?.step(id: "remove") {
                    transactionData = planned.transactionData
                } else {
                    transactionData = try await uniswapKit.removeLiquidityTransactionData(positions: item.positions, rpcSource: rpcSource, chain: chain, liquidity: liquidity, slippage: slippage, recipient: recipient, deadline: deadline)
                }

                try await send(transactionData: transactionData, gasLimit: matchingFeePlan(for: ratio)?.step(id: "remove")?.surchargedGasLimit)
                    .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .subscribe(onSuccess: { [weak self] tx in
                        self?.lastSubmittedTransactionHash = tx.transaction.hash.hs.hexString
                        self?.state = .removeSuccess

                    }, onError: { error in
                        let message = self.errorMessage(error: error, item: item)
                        self.state = .removeFailed(error: message)
                    })
                    .disposed(by: disposeBag)
            } catch {
                if lastSubmittedTransactionHash != nil {
                    state = .removeFailed(error: error.localizedDescription)
                } else {
                    state = .failed(error: error.localizedDescription)
                }
            }
        }
    }

    private func allowance(item: LiquidityV3RecordViewModel.V3RecordItem, ratio: BigUInt) async throws  {

        let evmKit = evmKitWrapper.evmKit
        let chain = evmKitWrapper.evmKit.chain

        let token0Address = item.positions.token0
        let token1Address = item.positions.token1
        let eip20Kit0 = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: token0Address)
        let eip20Kit1 = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: token1Address)

        let spenderAddress = uniswapKit.nonfungiblePositionAddress(chain: evmKit.chain)
        async let result0 = try eip20Kit0.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)
        async let result1 = try eip20Kit1.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)

        let liquidity = item.positions.liquidity * ratio / 100
        let (amount0, amount1, _) = try await uniswapKit.getAmountsForLiquidity(positions: item.positions, rpcSource: rpcSource, chain: chain, liquidity: liquidity)

        let allowance0 = try await BigUInt(result0) ?? 0
        let allowance1 = try await BigUInt(result1) ?? 0

        if  allowance0 < amount0  {
            try await approve(tokenAddress: token0Address, stepId: "approveToken0")
        }

        if allowance1 < amount1  {
            try await approve(tokenAddress: token1Address, stepId: "approveToken1")
        }
    }

    private func approve(tokenAddress: EvmKit.Address, stepId: String, transactionDataOverride: TransactionData? = nil) async throws {
        let evmKit = evmKitWrapper.evmKit

        guard let gasPrice = selectedGasPrice ?? legacyGasPrice else { throw LiquidityV3RecordError.noGasPrice }
        let nonce = try await takeNonce()
        let eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKit, contractAddress: tokenAddress)

        let spenderAddress = uniswapKit.nonfungiblePositionAddress(chain: evmKit.chain)
        let maxValue = BigUInt(Data(hex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
        let transactionData = transactionDataOverride ?? eip20Kit.approveTransactionData(spenderAddress: spenderAddress, amount: maxValue)

        let gasLimit: Int
        if let plannedGasLimit = matchingFeePlan(for: ratio)?.step(id: stepId)?.surchargedGasLimit {
            gasLimit = plannedGasLimit
        } else {
            gasLimit = try await evmKitWrapper.evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)
        }
        let transaction = try await evmKitWrapper.send(transactionData: transactionData, gasPrice: gasPrice, gasLimit: gasLimit, privateSend: false, nonce: nonce)
        lastSubmittedTransactionHash = transaction.transaction.hash.hs.hexString
    }

    private func send(transactionData: TransactionData, gasLimit plannedGasLimit: Int? = nil) async throws -> Single<FullTransaction> {

        guard let gasPrice = selectedGasPrice ?? legacyGasPrice else { return Single.error( LiquidityV3RecordError.noGasPrice) }
        let nonce = try await takeNonce()
        let gasLimit: Int
        if let plannedGasLimit {
            gasLimit = plannedGasLimit
        } else {
            gasLimit = try await evmKitWrapper.evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)
        }

        return evmKitWrapper.sendSingle(
                        transactionData: transactionData,
                        gasPrice: gasPrice,
                        gasLimit: gasLimit,
                        privateSend: false,
                        nonce: nonce
        )
    }

    private func takeNonce() async throws -> Int {
        if let nextNonceOverride {
            self.nextNonceOverride = nextNonceOverride + 1
            return nextNonceOverride
        }
        let nonce = try await evmKitWrapper.evmKit.nonce(defaultBlockParameter: .pending)
        nextNonceOverride = nonce + 1
        return nonce
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

    private func hasPendingRemovalTransaction(positionManager: EvmKit.Address) -> Bool {
        let owner = evmKitWrapper.evmKit.receiveAddress.hex.lowercased()

        return evmKitWrapper.evmKit.pendingTransactions(tagQueries: []).contains { fullTransaction in
            let transaction = fullTransaction.transaction
            guard transaction.from?.hex.lowercased() == owner,
                  transaction.to == positionManager,
                  let input = transaction.input,
                  input.count >= 4 else { return false }

            let selector = input.prefix(4).map { String(format: "%02x", $0) }.joined()
            switch selector {
            case "0c49ccbe": // decreaseLiquidity
                return true
            case "ac9650d8": // multicall(bytes[])
                return containsDecreaseLiquidity(inMulticallInput: input)
            default:
                return false
            }
        }
    }

    /// Checks the ABI encoded bytes[] passed to NonfungiblePositionManager.multicall.
    /// The bounds checks are intentional: pending transaction storage can contain
    /// externally-created or partially decoded input and must never crash the app.
    private func containsDecreaseLiquidity(inMulticallInput input: Data) -> Bool {
        let arguments = Data(input.dropFirst(4))
        guard let arrayOffset = readABINumber(arguments, at: 0),
              arrayOffset <= arguments.count - 32,
              let methodCount = readABINumber(arguments, at: arrayOffset),
              methodCount <= (arguments.count - arrayOffset - 32) / 32 else {
            return false
        }

        let offsetsStart = arrayOffset + 32
        for index in 0 ..< methodCount {
            let offsetPosition = offsetsStart + index * 32
            guard let methodOffset = readABINumber(arguments, at: offsetPosition),
                  methodOffset <= arguments.count - offsetsStart else {
                continue
            }

            let methodStart = offsetsStart + methodOffset
            guard let methodLength = readABINumber(arguments, at: methodStart),
                  methodLength >= 4,
                  methodLength <= arguments.count - methodStart - 32 else {
                continue
            }

            let selectorStart = methodStart + 32
            let methodSelector = arguments[selectorStart ..< selectorStart + 4]
                .map { String(format: "%02x", $0) }
                .joined()
            if methodSelector == "0c49ccbe" {
                return true
            }
        }

        return false
    }

    private func readABINumber(_ data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset <= data.count - 32 else { return nil }
        let value = BigUInt(data[offset ..< offset + 32])
        guard value <= BigUInt(Int.max) else { return nil }
        return Int(value)
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

    enum LiquidityV3RecordError: Error, UserFacingError {
        case invalidAddress
        case insufficientAmount
        case unsupportedToken
        case dataError
        case evmKitWrapperError
        case noGasPrice
        case pendingRemoval

        var errorDescription: String? {
            if case .pendingRemoval = self {
                return "transactions.pending".localized
            }
            return nil
        }
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
