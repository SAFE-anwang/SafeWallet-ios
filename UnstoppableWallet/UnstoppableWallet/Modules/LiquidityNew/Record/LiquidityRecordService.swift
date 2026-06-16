import Foundation
import RxSwift
import RxRelay
import MarketKit
import UniswapKit
import HsExtensions
import EvmKit
import BigInt
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
    private let rpcDataService: LiquidityRPCService
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


    init(marketKit: MarketKit.Kit, walletManager: WalletManager, adapterManager: AdapterManager, blockchainType: BlockchainType, rpcDataService: LiquidityRPCService = LiquidityRPCService()) {
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.adapterManager = adapterManager
        self.rpcDataService = rpcDataService

        self.currentBlockchainType = blockchainType

        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper else {
            return
        }
        self.evmKitWrapper = evmKitWrapper
        syncgasPrice(evmKitWrapper: evmKitWrapper)
    }

    func refresh() {
        syncItems()
    }

    private func syncItems() {
        state = .loading
        viewItems.removeAll()

        Task {
            do {
                guard let receiveAddress = getReceiveAddress() else {
                    state = .completed(datas: [])
                    return
                }

                // 使用 RPC 服务获取流动性位置
                let positions = try await rpcDataService.fetchV2LiquidityPositions(
                    user: receiveAddress.eip55,
                    blockchainType: currentBlockchainType
                )

                let items = try await buildRecordItems(from: positions)
                viewItems = items
                state = .completed(datas: viewItems)
            } catch {
                state = .failed(error: error.localizedDescription)
            }
        }
    }

    private func buildRecordItems(from positions: [V2LiquidityPosition]) async throws -> [LiquidityRecordViewModel.RecordItem] {
        // 仅查询所需 Token，避免全量拉取，显著提升性能
        let allTokens = try fetchTokens(for: positions)

        // 并发构建每个记录项，加速处理
        return try await withThrowingTaskGroup(of: LiquidityRecordViewModel.RecordItem?.self) { group in
            for position in positions {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return try await self.buildRecordItem(from: position, allTokens: allTokens)
                }
            }

            var items: [LiquidityRecordViewModel.RecordItem] = []
            for try await item in group {
                if let item { items.append(item) }
            }
            return items
        }
    }

    private func fetchTokens(for positions: [V2LiquidityPosition]) throws -> [MarketKit.Token] {
        var queries: [TokenQuery] = []
        var seen = Set<String>()

        for position in positions {
            let token0Address = position.pair.token0.id
            let token1Address = position.pair.token1.id

            let a0 = token0Address.lowercased()
            if !seen.contains(a0) {
                seen.insert(a0)
                queries.append(TokenQuery(blockchainType: currentBlockchainType, tokenType: .eip20(address: token0Address)))
            }

            let a1 = token1Address.lowercased()
            if !seen.contains(a1) {
                seen.insert(a1)
                queries.append(TokenQuery(blockchainType: currentBlockchainType, tokenType: .eip20(address: token1Address)))
            }
        }

        // 加上原生币，便于将 WETH 映射为 Native
        queries.append(TokenQuery(blockchainType: currentBlockchainType, tokenType: .native))

        return try marketKit.tokens(queries: queries)
    }

    private func buildRecordItem(from position: V2LiquidityPosition, allTokens: [MarketKit.Token]) async throws -> LiquidityRecordViewModel.RecordItem? {
        let pair = position.pair

        guard let token0 = getToken(from: pair.token0, allTokens: allTokens),
              let token1 = getToken(from: pair.token1, allTokens: allTokens) else {
            return nil
        }

        let token0Address = try address(token: token0)
        let token1Address = try address(token: token1)
        let token0RouterAddress = try routerAddress(token: token0)
        let token1RouterAddress = try routerAddress(token: token1)

        let pairItem0 = LiquidityPairItem(token: token0, address: token0Address, routerAddress: token0RouterAddress)
        let pairItem1 = LiquidityPairItem(token: token1, address: token1Address, routerAddress: token1RouterAddress)

        guard let evmKit = evmKitWrapper?.evmKit else { return nil }
        guard let liquidityPair = LiquidityPair.getPairAddress(
            evmKit: evmKit,
            itemA: pairItem0,
            itemB: pairItem1
        ) else {
            return nil
        }

        let poolInfo = PoolInfo(
            pooltToken0Amount: pair.reserve0BigInt,
            pooltToken1Amount: pair.reserve1BigInt,
            balanceOfAccount: position.liquidityTokenBalanceBigInt,
            poolTokenTotalSupply: pair.totalSupplyBigInt
        )

        guard poolInfo.balanceOfAccount > 0 else { return nil }

        return LiquidityRecordViewModel.RecordItem(poolInfo: poolInfo, pair: liquidityPair)
    }

    private func getToken(from v2Token: V2Token, allTokens: [MarketKit.Token]) -> MarketKit.Token? {
        if let token = allTokens.first(where: { token in
            token.blockchainType == currentBlockchainType &&
            token.type == .eip20(address: v2Token.id)
        }) {
            return token
        }

        if v2Token.id.lowercased() == (try? wethAddressString(chain: currentBlockchainType).lowercased()) {
            return nativeToken()
        }

        return nil
    }

    private func nativeToken() -> MarketKit.Token? {
        let query = TokenQuery(blockchainType: currentBlockchainType, tokenType: .native)
        return try? marketKit.token(query: query)
    }

    private func getReceiveAddress() -> EvmKit.Address? {
        guard let activeWallet = walletManager.activeWallets.first(where: { $0.token.blockchainType == currentBlockchainType }) else { return nil }
        guard let depositAdapter = adapterManager.depositAdapter(for: activeWallet) else { return nil }
        return try? EvmKit.Address(hex: depositAdapter.receiveAddress.address)
    }

}

extension LiquidityRecordService {

    private func address(token: MarketKit.Token) throws -> EvmKit.Address {
        switch token.type {
        case .native: return try EvmKit.Address(hex: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        case .eip20(let address): return try EvmKit.Address(hex: address)
        default: throw LiquidityRecordError.invalidAddress
        }
    }

    private func routerAddress(token: MarketKit.Token) throws -> EvmKit.Address {
        switch token.type {
        case .native: return try EvmKit.Address(hex: wethAddressString(chain: currentBlockchainType))
        case let .eip20(address): return try EvmKit.Address(hex: address)
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
        case .safe4: return "0x0000000000000000000000000000000000001101"
        default: throw UnsupportedChainError.noWethAddress
        }
    }

}

extension LiquidityRecordService {

    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }
}

extension LiquidityRecordService {

    func removeLiquidity(viewItem: LiquidityRecordViewModel.RecordItem, ratio: BigUInt) {
        state = .loading
        self.ratio = ratio
        debugLog("remove start ratio=\(ratio)% tokenA=\(viewItem.tokenA.coin.code) tokenB=\(viewItem.tokenB.coin.code) pair=\(viewItem.pair.pairAddress.eip55) lpBalance=\(viewItem.poolInfo.balanceOfAccount) token0Amount=\(viewItem.poolInfo.userToken0Amount) token1Amount=\(viewItem.poolInfo.userToken1Amount)")
        Task {
            do {
                guard let receiveAddress = getReceiveAddress() else {
                    debugLog("remove failed before send: missing receive address")
                    throw LiquidityRecordError.invalidAddress
                }
                guard let evmKitWrapper = evmKitWrapper else {
                    debugLog("remove failed before send: missing evmKitWrapper")
                    throw LiquidityRecordError.evmKitWrapperError
                }
                
                let pairAddress = viewItem.pair.pairAddress
                let poolInfo = viewItem.poolInfo
                debugLog("remove context chain=\(evmKitWrapper.evmKit.chain) account=\(receiveAddress.eip55) pair=\(pairAddress.eip55)")
                await logPairDiagnostics(pairAddress: pairAddress, viewItem: viewItem, poolInfo: poolInfo)
                
                // 首先尝试使用 Permit 方式（无需预先 approve）
                do {
                    try await removeWithPermit(
                        viewItem: viewItem,
                        pairAddress: pairAddress,
                        receiveAddress: receiveAddress,
                        poolInfo: poolInfo
                    )
                    return
                } catch let error as PermitError {
                    debugLog("permit path unavailable, fallback to approve/remove error=\(error.localizedDescription)")
                    // Permit 失败，回退到传统 approve + remove 方式
                    let eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKitWrapper.evmKit, contractAddress: pairAddress)
                    try await checkAllowanceAndRemove(eip20Kit: eip20Kit, viewItem: viewItem, pairAddress: pairAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
                }
            } catch {
                debugLog("remove failed before subscription error=\(describe(error))")
                state = .failed(error: error.localizedDescription)
            }
        }
    }

    /// 使用 EIP-2612 Permit 签名移除流动性（无需预先 approve）
    private func removeWithPermit(viewItem: LiquidityRecordViewModel.RecordItem, pairAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        guard let evmKitWrapper else {
            throw LiquidityRecordError.evmKitWrapperError
        }
        guard let signer = evmKitWrapper.signer else {
            throw LiquidityRecordError.evmKitWrapperError
        }

        let evmKit = evmKitWrapper.evmKit
        let routerAddressString = try Constants.routerAddressString(chain: evmKit.chain)
        let routerAddress = try EvmKit.Address(hex: routerAddressString)

        let addressA = viewItem.pair.item0.routerAddress
        let addressB = viewItem.pair.item1.routerAddress
        let slippage: (BigUInt, BigUInt) = (5, 1000)
        let amountAExpected = viewItem.poolInfo.userToken0Amount * ratio / 100
        let amountBExpected = viewItem.poolInfo.userToken1Amount * ratio / 100
        let amountAMin = amountAExpected * (slippage.1 - slippage.0) / slippage.1
        let amountBMin = amountBExpected * (slippage.1 - slippage.0) / slippage.1

        let deadline = Constants.getDeadLine()
        let liquidity = poolInfo.balanceOfAccount * ratio / 100

        // 获取 Permit 所需参数
        let nonce: BigUInt
        let name: String
        do {
            nonce = try await getNonces(evmKit: evmKit, contractAddress: pairAddress, receiveAddress: receiveAddress)
            name = try await getName(evmKit: evmKit, contractAddress: pairAddress)
            try await validatePermitMetadata(evmKit: evmKit, contractAddress: pairAddress, name: name)
        } catch {
            throw PermitError.permitNotSupported
        }
        
        let chainId = evmKit.chain.id

        // 生成 EIP-712 签名
        let signature: Data
        do {
            signature = try signer.sign(eip712TypedData: try buildPermitTypedData(
                name: name,
                chainId: chainId,
                verifyingContract: pairAddress.eip55,
                owner: receiveAddress.eip55,
                spender: routerAddress.eip55,
                value: liquidity,
                nonce: nonce,
                deadline: deadline
            ))
        } catch {
            throw PermitError.signatureFailed(error)
        }

        // 解析签名组件
        let (v, r, s) = try parseSignatureComponents(signature: signature)

        // 构建 RemoveLiquidityWithPermit 交易
        let transactionData: EvmKit.TransactionData
        if case .native = viewItem.pair.item0.token.type {
            let method = RemoveLiquidityEthWithPermitMethod(
                token: addressB,
                liquidity: liquidity,
                amountTokenMin: amountBMin,
                amountEthMin: amountAMin,
                to: receiveAddress,
                deadline: deadline,
                approveMax: false,
                v: BigUInt(v),
                r: r,
                s: s
            )
            transactionData = EvmKit.TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        } else if case .native = viewItem.pair.item1.token.type {
            let method = RemoveLiquidityEthWithPermitMethod(
                token: addressA,
                liquidity: liquidity,
                amountTokenMin: amountAMin,
                amountEthMin: amountBMin,
                to: receiveAddress,
                deadline: deadline,
                approveMax: false,
                v: BigUInt(v),
                r: r,
                s: s
            )
            transactionData = EvmKit.TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        } else {
            let method = RemoveLiquidityWithPermitMethod(
                tokenA: addressA,
                tokenB: addressB,
                liquidity: liquidity,
                amountAMin: amountAMin,
                amountBMin: amountBMin,
                to: receiveAddress,
                deadline: deadline,
                approveMax: false,
                v: BigUInt(v),
                r: r,
                s: s
            )
            transactionData = EvmKit.TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        }

        debugLog("permit remove tx prepared router=\(routerAddress.eip55) tokenA=\(addressA.eip55) tokenB=\(addressB.eip55) liquidity=\(liquidity) amountAMin=\(amountAMin) amountBMin=\(amountBMin) deadline=\(deadline) input=\(shortInput(transactionData.input))")

        try await send(transactionData: transactionData, context: "removeWithPermit")
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] tx in
                guard let self else { return }
                self.debugLog("permit remove send success tx=\(String(describing: tx))")
                if let index = self.viewItems.firstIndex(where: { $0.pair.pairAddress == viewItem.pair.pairAddress }) {
                    self.viewItems.remove(at: index)
                    self.state = .removeSuccess
                }
            }, onError: { [weak self] error in
                guard let self else { return }
                self.debugLog("permit remove send error=\(self.describe(error))")
                let message = self.errorMessage(error: error, item: viewItem)
                self.state = .removeFailed(error: message)
            })
            .disposed(by: disposeBag)
    }

    /// 检查 allowance，如不足则先 approve，然后移除流动性
    private func checkAllowanceAndRemove(eip20Kit: Eip20Kit.Kit, viewItem: LiquidityRecordViewModel.RecordItem, pairAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        guard let evmKit = evmKitWrapper?.evmKit else {
            throw LiquidityRecordError.evmKitWrapperError
        }
        let routerAddressString = try Constants.routerAddressString(chain: evmKit.chain)
        let routerAddress = try EvmKit.Address(hex: routerAddressString)
        
        let liquidity = poolInfo.balanceOfAccount * ratio / 100
        debugLog("allowance check router=\(routerAddress.eip55) pair=\(pairAddress.eip55) requiredLP=\(liquidity)")
        
        // 查询当前 allowance
        let allowanceResult: BigUInt
        do {
            let allowanceString = try await eip20Kit.allowance(spenderAddress: routerAddress, defaultBlockParameter: .latest)
            allowanceResult = BigUInt(allowanceString) ?? 0
            debugLog("allowance result raw=\(allowanceString) parsed=\(allowanceResult) required=\(liquidity)")
        } catch {
            debugLog("allowance check error=\(describe(error))")
            throw LiquidityRecordError.allowanceCheckFailed
        }
        
        // 如果 allowance 足够，直接移除流动性
        if allowanceResult >= liquidity {
            debugLog("allowance enough, remove directly")
            try await removeLiquidityDirectly(viewItem: viewItem, routerAddress: routerAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
        } else {
            // 需要 approve
            debugLog("allowance not enough, approve first allowance=\(allowanceResult) required=\(liquidity)")
            try await approveAndRemove(eip20Kit: eip20Kit, viewItem: viewItem, routerAddress: routerAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
        }
    }

    /// 执行 approve 然后移除流动性
    private func approveAndRemove(eip20Kit: Eip20Kit.Kit, viewItem: LiquidityRecordViewModel.RecordItem, routerAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        let maxValue = BigUInt(Data(hex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
        let transactionData = eip20Kit.approveTransactionData(spenderAddress: routerAddress, amount: maxValue)
        debugLog("approve tx prepared router=\(routerAddress.eip55) amount=max input=\(shortInput(transactionData.input))")
        
        try await send(transactionData: transactionData, context: "approveLP")
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] tx in
                guard let self = self else { return }
                self.debugLog("approve send success tx=\(String(describing: tx)); starting remove immediately")
                Task {
                    do {
                        try await self.removeLiquidityDirectly(viewItem: viewItem, routerAddress: routerAddress, receiveAddress: receiveAddress, poolInfo: poolInfo)
                    } catch {
                        self.debugLog("remove after approve threw before subscription error=\(self.describe(error))")
                        self.state = .removeFailed(error: error.localizedDescription)
                    }
                }
            }, onError: { [weak self] error in
                self?.debugLog("approve send error=\(self?.describe(error) ?? String(describing: error))")
                self?.state = .approveFailed
            })
            .disposed(by: disposeBag)
    }

    /// 直接移除流动性（已授权）
    private func removeLiquidityDirectly(viewItem: LiquidityRecordViewModel.RecordItem, routerAddress: EvmKit.Address, receiveAddress: EvmKit.Address, poolInfo: PoolInfo) async throws {
        let addressA = viewItem.pair.item0.routerAddress
        let addressB = viewItem.pair.item1.routerAddress
        let slippage: (BigUInt, BigUInt) = (5, 1000)
        let amountAExpected = viewItem.poolInfo.userToken0Amount * ratio / 100
        let amountBExpected = viewItem.poolInfo.userToken1Amount * ratio / 100
        let amountAMin = amountAExpected * (slippage.1 - slippage.0) / slippage.1
        let amountBMin = amountBExpected * (slippage.1 - slippage.0) / slippage.1

        let deadline = Constants.getDeadLine()
        let liquidity = poolInfo.balanceOfAccount * ratio / 100

        let transactionData: EvmKit.TransactionData
        if case .native = viewItem.pair.item0.token.type {
            let method = RemoveLiquidityEthMethod(
                token: addressB,
                liquidity: liquidity,
                amountTokenMin: amountBMin,
                amountEthMin: amountAMin,
                to: receiveAddress,
                deadline: deadline
            )
            transactionData = EvmKit.TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        } else if case .native = viewItem.pair.item1.token.type {
            let method = RemoveLiquidityEthMethod(
                token: addressA,
                liquidity: liquidity,
                amountTokenMin: amountAMin,
                amountEthMin: amountBMin,
                to: receiveAddress,
                deadline: deadline
            )
            transactionData = EvmKit.TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        } else {
            let method = RemoveLiquidityMethod(
                tokenA: addressA,
                tokenB: addressB,
                liquidity: liquidity,
                amountAMin: amountAMin,
                amountBMin: amountBMin,
                to: receiveAddress,
                deadline: deadline
            )
            transactionData = EvmKit.TransactionData(to: routerAddress, value: 0, input: method.encodedABI())
        }
        debugLog("remove tx prepared router=\(routerAddress.eip55) tokenA=\(addressA.eip55) tokenB=\(addressB.eip55) liquidity=\(liquidity) amountAMin=\(amountAMin) amountBMin=\(amountBMin) deadline=\(deadline) input=\(shortInput(transactionData.input))")
        
        try await send(transactionData: transactionData, context: "removeLiquidity")
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] tx in
                guard let self else { return }
                self.debugLog("remove send success tx=\(String(describing: tx))")
                if let index = self.viewItems.firstIndex(where: { $0.pair.pairAddress == viewItem.pair.pairAddress }) {
                    self.viewItems.remove(at: index)
                    self.state = .removeSuccess
                }
            }, onError: { [weak self] error in
                guard let self else { return }
                self.debugLog("remove send error=\(self.describe(error))")
                let message = self.errorMessage(error: error, item: viewItem)
                self.state = .removeFailed(error: message)
            })
            .disposed(by: disposeBag)
    }

    private func send(transactionData: TransactionData, context: String) async throws -> Single<FullTransaction> {
        guard let evmKitWrapper = evmKitWrapper else {
            debugLog("send[\(context)] missing evmKitWrapper")
            return Single.error(LiquidityRecordError.evmKitWrapperError)
        }
        debugLog("send[\(context)] preparing to=\(transactionData.to.eip55) value=\(transactionData.value) input=\(shortInput(transactionData.input))")
        let nonce = try await evmKitWrapper.evmKit.nonce(defaultBlockParameter: .pending)
        debugLog("send[\(context)] nonce=\(nonce)")
        guard let gasPrice = legacyGasPrice else {
            debugLog("send[\(context)] missing gasPrice")
            return Single.error(LiquidityRecordError.noGasPrice)
        }
        debugLog("send[\(context)] gasPrice=\(String(describing: gasPrice))")
        let gasLimit: Int
        do {
            gasLimit = try await evmKitWrapper.evmKit.fetchEstimateGas(transactionData: transactionData, gasPrice: gasPrice)
        } catch {
            debugLog("send[\(context)] estimateGas error=\(describe(error))")
            throw error
        }
        debugLog("send[\(context)] estimatedGasLimit=\(gasLimit)")

        return evmKitWrapper.sendSingle(
                        transactionData: transactionData,
                        gasPrice: gasPrice,
                        gasLimit: gasLimit,
                        privateSend: false,
                        nonce: nonce
                )
    }

    private func syncgasPrice(evmKitWrapper: EvmKitWrapper) {
        let gasPriceProvider = LegacyGasPriceProvider(evmKit: evmKitWrapper.evmKit)
        gasPriceProvider.gasPriceSingle()
            .subscribe(
                onSuccess: { [weak self] gasPrice in
                    self?.legacyGasPrice =  gasPrice
                    self?.debugLog("gas price synced gasPrice=\(String(describing: gasPrice))")
                },
                onError: { [weak self] error in
                    self?.debugLog("gas price sync error=\(self?.describe(error) ?? String(describing: error))")
                    self?.state = .gasPriceFailed
                }
            )
            .disposed(by: disposeBag)
    }

    func errorMessage(error: Error, item: LiquidityRecordViewModel.RecordItem) -> String {
        if let revertReason = revertReason(from: error) {
            if revertReason.contains("TRANSFER_FAILED") {
                return "liquidity.remove.error.transfer_failed".localized(item.tokenA.coin.code, item.tokenB.coin.code)
            }

            return "liquidity.remove.error.execution_reverted".localized(revertReason)
        }

        if case JsonRpcResponse.ResponseError.rpcError(_) = error {
            let feeType: String
            switch item.tokenA.blockchainType {
            case .binanceSmartChain:
                feeType = "BNB"
            case .ethereum:
                feeType = "ETH"
            case .safe4:
                feeType = "SAFE"
            default:
                feeType = ""
            }
            return "liquidity.remove.error.insufficient".localized(feeType)
        }
        return error.localizedDescription
    }

    private func debugLog(_ message: String) {
        print("[LiquidityRemove][SAFE] \(message)")
    }

    private func describe(_ error: Error) -> String {
        if let revertReason = revertReason(from: error) {
            return "\(type(of: error)): \(error.localizedDescription) | revertReason=\(revertReason) | \(String(describing: error))"
        }
        return "\(type(of: error)): \(error.localizedDescription) | \(String(describing: error))"
    }

    private func shortInput(_ input: Data) -> String {
        let hex = input.hs.hexString
        guard hex.count > 20 else {
            return "0x\(hex)"
        }
        return "0x\(hex.prefix(20))...(\(input.count) bytes)"
    }

    private func revertReason(from error: Error) -> String? {
        guard case let JsonRpcResponse.ResponseError.rpcError(rpcError) = error else {
            return nil
        }

        if let data = rpcError.data {
            let dataHex = String(describing: data)
            if let reason = decodeRevertReason(dataHex: dataHex) {
                return reason
            }
        }

        if rpcError.message.contains("execution reverted") {
            return rpcError.message
        }

        return nil
    }

    private func decodeRevertReason(dataHex: String) -> String? {
        let unwrapped: String
        if dataHex.hasPrefix("Optional("), dataHex.hasSuffix(")") {
            unwrapped = String(dataHex.dropFirst("Optional(".count).dropLast())
        } else {
            unwrapped = dataHex
        }

        let cleaned = unwrapped.hasPrefix("0x") ? String(unwrapped.dropFirst(2)) : unwrapped
        guard cleaned.count >= 8 else {
            return nil
        }
        let selector = String(cleaned.prefix(8))
        guard selector == "08c379a0" else {
            return nil
        }
        guard let data = Data(hex: cleaned), data.count >= 4 + 32 + 32 else {
            return nil
        }

        let payload = data.dropFirst(4)
        guard payload.count >= 64 else {
            return nil
        }

        let lengthStart = payload.startIndex + 32
        let lengthEnd = lengthStart + 32
        let lengthData = payload[lengthStart..<lengthEnd]
        let length = Int(BigUInt(lengthData))
        let stringStart = lengthEnd
        let stringEnd = stringStart + length

        guard payload.count >= stringEnd else {
            return nil
        }

        return String(data: payload[stringStart..<stringEnd], encoding: .utf8)
    }

    private func logPairDiagnostics(pairAddress: EvmKit.Address, viewItem: LiquidityRecordViewModel.RecordItem, poolInfo: PoolInfo) async {
        guard let evmKit = evmKitWrapper?.evmKit else {
            return
        }

        do {
            async let token0 = getPairToken0(evmKit: evmKit, contractAddress: pairAddress)
            async let token1 = getPairToken1(evmKit: evmKit, contractAddress: pairAddress)
            async let reserves = getReserves(evmKit: evmKit, contractAddress: pairAddress)
            async let totalSupply = getTotalSupply(evmKit: evmKit, contractAddress: pairAddress)

            let (pairToken0, pairToken1, pairReserves, pairTotalSupply) = try await (token0, token1, reserves, totalSupply)
            debugLog(
                """
                pair diagnostics token0=\(pairToken0.eip55) token1=\(pairToken1.eip55) \
                reserve0=\(pairReserves.0) reserve1=\(pairReserves.1) totalSupply=\(pairTotalSupply) \
                uiTokenA=\(viewItem.pair.item0.address.eip55) uiTokenB=\(viewItem.pair.item1.address.eip55) \
                userShareToken0=\(poolInfo.userToken0Amount) userShareToken1=\(poolInfo.userToken1Amount)
                """
            )
        } catch {
            debugLog("pair diagnostics error pair=\(pairAddress.eip55) error=\(describe(error))")
        }
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

    private func getName(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> String {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetNameMethod().encodedABI())
        guard data.count >= 64 else {
            throw LiquidityRecordError.invalidAddress
        }

        let offset = Int(BigUInt(data[0 ..< 32]))
        guard data.count >= offset + 32 else {
            throw LiquidityRecordError.invalidAddress
        }

        let length = Int(BigUInt(data[offset ..< offset + 32]))
        let start = offset + 32
        let end = start + length

        guard data.count >= end else {
            throw LiquidityRecordError.invalidAddress
        }

        guard let name = String(data: data[start ..< end], encoding: .utf8) else {
            throw LiquidityRecordError.invalidAddress
        }

        return name
    }

    /// 构建符合 EIP-2612 标准的 Permit EIP-712 TypedData
    private func buildPermitTypedData(name: String, chainId: Int, verifyingContract: String, owner: String, spender: String, value: BigUInt, nonce: BigUInt, deadline: BigUInt) throws -> EvmKit.EIP712TypedData {
        let escapedName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // EIP-2612 Permit 标准结构
        let json = """
        {
          "types": {
            "EIP712Domain": [
              { "name": "name", "type": "string" },
              { "name": "version", "type": "string" },
              { "name": "chainId", "type": "uint256" },
              { "name": "verifyingContract", "type": "address" }
            ],
            "Permit": [
              { "name": "owner", "type": "address" },
              { "name": "spender", "type": "address" },
              { "name": "value", "type": "uint256" },
              { "name": "nonce", "type": "uint256" },
              { "name": "deadline", "type": "uint256" }
            ]
          },
          "primaryType": "Permit",
          "domain": {
            "name": "\(escapedName)",
            "version": "1",
            "chainId": \(chainId),
            "verifyingContract": "\(verifyingContract)"
          },
          "message": {
            "owner": "\(owner)",
            "spender": "\(spender)",
            "value": "\(value)",
            "nonce": "\(nonce)",
            "deadline": "\(deadline)"
          }
        }
        """

        guard let data = json.data(using: .utf8) else {
            throw LiquidityRecordError.dataError
        }

        return try EvmKit.EIP712TypedData.parseFrom(rawJson: data)
    }

    /// 解析签名组件，返回符合 EIP-2612 标准的 v, r, s
    /// - r: 32 字节 Data
    /// - s: 32 字节 Data
    /// - v: 27 或 28 (或 0/1)
    private func parseSignatureComponents(signature: Data) throws -> (UInt8, Data, Data) {
        guard signature.count == 65 else {
            throw LiquidityRecordError.invalidSignature
        }

        let r = signature[0..<32]
        let s = signature[32..<64]
        var v = signature[64]
        
        // 将 v 从 0/1 转换为 27/28 (EIP-155 兼容)
        if v < 27 {
            v += 27
        }
        
        // 验证 v 值
        guard v == 27 || v == 28 else {
            throw LiquidityRecordError.invalidSignature
        }

        return (v, Data(r), Data(s))
    }

    private func validatePermitMetadata(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address, name: String) async throws {
        let onChainDomainSeparator = try await getDomainSeparator(evmKit: evmKit, contractAddress: contractAddress)
        let onChainPermitTypeHash = try await getPermitTypeHash(evmKit: evmKit, contractAddress: contractAddress)

        let expectedDomainSeparator = try expectedDomainSeparator(
            name: name,
            chainId: evmKit.chain.id,
            verifyingContract: contractAddress
        )
        let expectedPermitTypeHash = expectedPermitTypeHash()

        debugLog(
            """
            permit metadata domainSeparator.onChain=0x\(onChainDomainSeparator.hs.hexString) \
            domainSeparator.expected=0x\(expectedDomainSeparator.hs.hexString) \
            permitTypeHash.onChain=0x\(onChainPermitTypeHash.hs.hexString) \
            permitTypeHash.expected=0x\(expectedPermitTypeHash.hs.hexString)
            """
        )

        guard onChainDomainSeparator == expectedDomainSeparator,
              onChainPermitTypeHash == expectedPermitTypeHash else {
            throw PermitError.permitNotSupported
        }
    }

    private func expectedDomainSeparator(name: String, chainId: Int, verifyingContract: EvmKit.Address) throws -> Data {
        let domainTypeHash = Crypto.sha3("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".data(using: .utf8) ?? Data())
        let nameHash = Crypto.sha3(name.data(using: .utf8) ?? Data())
        let versionHash = Crypto.sha3("1".data(using: .utf8) ?? Data())
        let encoded =
            abiEncodeBytes32(domainTypeHash) +
            abiEncodeBytes32(nameHash) +
            abiEncodeBytes32(versionHash) +
            abiEncodeUint256(BigUInt(chainId)) +
            abiEncodeAddress(verifyingContract)
        return Crypto.sha3(encoded)
    }

    private func expectedPermitTypeHash() -> Data {
        Crypto.sha3("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)".data(using: .utf8) ?? Data())
    }

    private func abiEncodeUint256(_ value: BigUInt) -> Data {
        let raw = value.serialize()
        return Data(repeating: 0, count: max(0, 32 - raw.count)) + raw
    }

    private func abiEncodeAddress(_ address: EvmKit.Address) -> Data {
        Data(repeating: 0, count: 12) + address.raw
    }

    private func abiEncodeBytes32(_ data: Data) -> Data {
        if data.count == 32 {
            return data
        }

        if data.count > 32 {
            return Data(data.suffix(32))
        }

        return data + Data(repeating: 0, count: 32 - data.count)
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

    private func getPairToken0(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> EvmKit.Address {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetToken0Method().encodedABI())
        guard data.count >= 32 else {
            throw LiquidityRecordError.dataError
        }
        return EvmKit.Address(raw: data.suffix(20))
    }

    private func getPairToken1(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> EvmKit.Address {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetToken1Method().encodedABI())
        guard data.count >= 32 else {
            throw LiquidityRecordError.dataError
        }
        return EvmKit.Address(raw: data.suffix(20))
    }

    private func getDomainSeparator(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> Data {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: DomainSeparatorMethod().encodedABI())
        guard data.count >= 32 else {
            throw LiquidityRecordError.dataError
        }
        return Data(data.prefix(32))
    }

    private func getPermitTypeHash(evmKit: EvmKit.Kit, contractAddress: EvmKit.Address) async throws -> Data {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: PermitTypeHashMethod().encodedABI())
        guard data.count >= 32 else {
            throw LiquidityRecordError.dataError
        }
        return Data(data.prefix(32))
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
        case invalidSignature
        case allowanceCheckFailed
    }

    enum LiquidityABIError: Error {
        case getNameError
        case getNoncesError
        case getTotalSupplyError
        case getReservesError
        case getBalanceOfError
    }

    /// Permit 相关错误
    enum PermitError: Error {
        case permitNotSupported
        case signatureFailed(Error)
        case invalidSignatureComponents

        var localizedDescription: String {
            switch self {
            case .permitNotSupported:
                return "LP Token does not support EIP-2612 Permit"
            case .signatureFailed(let error):
                return "Signature generation failed: \(error.localizedDescription)"
            case .invalidSignatureComponents:
                return "Invalid signature components"
            }
        }
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
