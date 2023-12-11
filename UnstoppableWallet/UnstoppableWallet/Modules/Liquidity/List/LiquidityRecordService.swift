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
    
    init(marketKit: MarketKit.Kit, walletManager: WalletManager, adapterManager: AdapterManager, evmKitWrapper: EvmKitWrapper, swapKit: UniswapKit.Kit) {
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.adapterManager = adapterManager
        self.evmKitWrapper = evmKitWrapper
        self.evmKit = evmKitWrapper.evmKit
        self.swapKit = swapKit
        
        syncItems()
    }
    
    private func syncItems() {
            
        let tokenQuerys = activeWallets.compactMap { TokenQuery(blockchainType: .binanceSmartChain, tokenType: $0.token.type) }
        
        guard let tokens = try? marketKit.tokens(queries: tokenQuerys) else { return }
        
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
                                                       pairAddress: pairAddress)
        }catch {
            return nil
        }
    }
    
    private func signer(account: Account, chain: Chain) throws -> Signer? {
        var signer: Signer?
        switch account.type {
        case .mnemonic:
            guard let seed = account.type.mnemonicSeed else { return nil }
            signer = try Signer.instance(seed: seed, chain: chain)
        case let .evmPrivateKey(data):
            signer = Signer.instance(privateKey: data, chain: chain)
        default: ()
        }
        return signer
    }
    
    func removeLiquidity(viewItem: LiquidityRecordViewModel.RecordItem) {
        Task {
            do {
                guard let item = viewItems.first(where: { viewItem.pairAddress == $0.pairAddress }) else{ return }
                guard let wallet = getWallet(token: item.tokenA), let receiveAddress = getReceiveAddress(wallet: wallet) else{ return }
                guard let signer = try signer(account: wallet.account, chain: evmKit.chain) else { return }
                let pairAddress = viewItem.pairAddress
                

//                try await testRemove()
                let nonce = try await getNonces(contractAddress: pairAddress, receiveAddress: receiveAddress)
                let txNonce = try await evmKit.nonce(defaultBlockParameter: .pending)
                guard let contractAddress = try? EvmKit.Address(hex: Constants.DEX.PANCAKE_V2_ROUTER_ADDRESS) else { return }

                let poolInfo = try await liquiditypoolInfo(pairAddress: pairAddress, receiveAddress: receiveAddress)
                let shareRate = (Decimal(bigUInt: poolInfo.balanceOfAccount, decimals: 0) ?? 0) / (Decimal(bigUInt: poolInfo.poolTokenTotalSupply, decimals: 0) ?? 0)

                let addressA = try address(token: item.tokenA)
                let addressB = try address(token: item.tokenB)
                
                let decimalAMin = (Decimal(bigUInt: poolInfo.reserves.0, decimals: 0) ?? 0) * shareRate * Constants.slippage
                let decimalBMin = (Decimal(bigUInt: poolInfo.reserves.1, decimals: 0) ?? 0) * shareRate * Constants.slippage
                let amountAMin = BigUInt(decimalAMin.hs.roundedString(decimal: 0)) ?? 0
                let amountBMin = BigUInt(decimalBMin.hs.roundedString(decimal: 0)) ?? 0
                let liquidity = poolInfo.balanceOfAccount

                let deadline = Constants.getDeadLine() // (UInt64(Date().timeIntervalSince1970) + UInt64(60 * Constants.deadLine))//

                let domainSeparator = try await getDomainSeparator(contractAddress: pairAddress)
                
                let eip20Kit = try Eip20Kit.Kit.instance(evmKit: evmKitWrapper.evmKit, contractAddress: pairAddress)
                let eip20KitTransactionData = eip20Kit.approveTransactionData(spenderAddress: contractAddress, amount: liquidity)

//                let addressA = try EvmKit.Address(hex: "0x4d7Fa587Ec8e50bd0E9cD837cb4DA796f47218a1")
//                let addressB = try EvmKit.Address(hex: "0x55d398326f99059fF775485246999027B3197955")
//                let liquidity = BigUInt(530165123103431)
//                let amountAMin = BigUInt(427978059874830)
//                let amountBMin = BigUInt(992014996981108)
//                let to = try EvmKit.Address(hex:"0x6d0897776FAc2A97D739DEa013a15bF19498A33e")
//                let deadline = BigUInt(1701872111)
//                let nonce = BigUInt(632)//try await getNonces(contractAddress: pairAddress, receiveAddress: receiveAddress)
//                let approveMax = false
                
//                [8]:  000000000000000000000000000000000000000000000000000000000000001b
//                [9]:  1052bcd22d8e6f9e1c2f5a480bfdb91a6fa842d551545d69823142f06f6bacd4
//                [10]: 543814210eb3fbed0f74e546ad04538f41bc7fa6676b09e5db03d7d198f77836
//                let v = BigUInt(27)
//                let r = Data(hex: "0x1052bcd22d8e6f9e1c2f5a480bfdb91a6fa842d551545d69823142f06f6bacd4")
//                let s = Data(hex: "0x543814210eb3fbed0f74e546ad04538f41bc7fa6676b09e5db03d7d198f77836")
                
                
                
//                debugPrint("domainSeparator Get: \(domainSeparator.hs.reversedHex)\n")
                let domain = Domain(name: "Pancake LPs", version: "1", chainId: evmKit.chain.id, verifyingContract: pairAddress.hex)
                let message = Message(owner: receiveAddress.hex, spender: Constants.DEX.PANCAKE_V2_ROUTER_ADDRESS, value: (Decimal(bigUInt: liquidity, decimals: 0) ?? 0), nonce: Int(nonce), deadline: UInt64(deadline))
                let permit = PermitData(types: Types(), primaryType: "Permit", domain: domain, message: message)
                let permitData = try permit.encode()
                
////
                ///
                
                let eip712TypedData = try EIP712TypedData.parseFrom(rawJson: permitData)
                let signData = try signer.sign(eip712TypedData: eip712TypedData)
                let (v, r, s) = signatureEip712(from: signData)
                print("EIP712_VRS >>> r:\(r.hexString), s:\(s.hexString)")
//
//                let messageP = PermitMessage(owner: EIP712.Address(receiveAddress.hex)!,
//                                            spender: EIP712.Address(Constants.DEX.PANCAKE_V2_ROUTER_ADDRESS)!,
//                                            value: liquidity,
//                                            nonce: nonce,
//                                            deadline: EIP712.UInt256(deadline)
//                )
//                let signData = try await TransactionContractSend.testWithSignEIP712(message: permitData, pairAddress: pairAddress.hex, receiveAddress: receiveAddress.hex,privateKey: signer.getPrivateKey(), permitMessage: messageP)
//                let (v, r, s) = signatureEip712(from: signData)
//                print("EIP712_VRS >>> v:\(v),r:\(r.hs.hexString), s:\(s.hs.hexString)")
//                debugPrint("signature web3swift: \(signaturedd.hs.reversedHex)")
                

//                let permitDataHash = getPermitDataHash(domainSeparator: domainSeparator, message: message)
//                let signHash = try Crypto.ellipticSign(permitDataHash, privateKey: signer.getPrivateKey())
//                let (v, r, s) = signatureEip712(from: signHash)
                
                
//                let method = RemoveLiquidityWithPermitMethod(tokenA: addressA, tokenB: addressB, liquidity: liquidity, amountAMin: amountAMin, amountBMin: amountBMin, to: receiveAddress, deadline: deadline, approveMax: false, v: BigUInt(v), r: r, s: s)
//                let transactionData = EvmKit.TransactionData(to: contractAddress, value: 0, input: method.encodedABI())
//                let gasPrice = GasPrice.legacy(gasPrice: FeePriceScale.gwei.scaleValue * 10)
//                evmKitWrapper.sendSingle(
//                                transactionData: transactionData,
//                                gasPrice: gasPrice,
//                                gasLimit: 500000,
//                                nonce: txNonce
//                        )
//                        .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
//                        .subscribe(onSuccess: { [weak self] fullTransaction in
//                            print("Success")
//                            //self?.sendState = .sent(transactionHash: fullTransaction.transaction.hash)
//                        }, onError: { error in
//                            print(error)
//                            //self.sendState = .failed(error: error)
//                        })
//                        .disposed(by: disposeBag)
//
//                syncItems()
        //            state = .completed(data: viewItems)
              

            }catch {
                state = .failed(error: LiquidityRecordError.dataError)
            }
        }
    }
    
    private func getPermitDataHash(domainSeparator: Data, message: Message) -> Data {
        let messageData = Constants.PERMIT_TYPEHASH.hs.data
                            + message.owner.hs.data
                            + message.spender.hs.data
                            + Data(from: message.value)
                            + Data(from: message.nonce)
                            + Data(from: message.deadline)
        let permitData = Data([0x19, 0x01]) + domainSeparator + Crypto.sha3(messageData)
        return  Crypto.sha3(permitData)
    }


}

extension LiquidityRecordService {
    private func getName(contractAddress: EvmKit.Address) async throws -> String {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetNameMethod().encodedABI())
        return data.hs.to(type: String.self)
    }
    
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
    
    private func getDomainSeparator(contractAddress: EvmKit.Address) async throws -> Data {
        let data = try await evmKit.fetchCall(contractAddress: contractAddress, data: GetDomainSeparatorMethod().encodedABI())
        return data
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
        case failed(error: Error)
    }
}

extension LiquidityRecordService {

    private func signatureEip712(from data: Data) -> (Int, BigUInt, BigUInt) {
        (
            v: Int(data[64]) + 27,
            r: BigUInt(data[..<32].hs.hex, radix: 16)!,
            s: BigUInt(data[32..<64].hs.hex, radix: 16)!
        )
    }
}
