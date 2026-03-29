import Foundation
import MarketKit
import EvmKit
import BigInt
import UniswapKit
import RxSwift

// MARK: - ChainLiquidityProvider
// 单链流动性数据提供者，处理特定链的流动性查询

class ChainLiquidityProvider {
    let config: ChainConfig
    private let marketKit: MarketKit.Kit
    private let walletManager: WalletManager
    private let adapterManager: AdapterManager
    private let rpcService: LiquidityRPCService
    
    init(
        config: ChainConfig,
        marketKit: MarketKit.Kit,
        walletManager: WalletManager,
        adapterManager: AdapterManager,
        rpcService: LiquidityRPCService
    ) {
        self.config = config
        self.marketKit = marketKit
        self.walletManager = walletManager
        self.adapterManager = adapterManager
        self.rpcService = rpcService
    }
}

// MARK: - 公共方法

extension ChainLiquidityProvider {
    
    /// 获取该链的所有流动性记录
    func fetchLiquidityRecords() async throws -> [ChainLiquidityRecord] {
        var records: [ChainLiquidityRecord] = []
        
        // 获取 V2 流动性
        let v2Records = try await fetchV2Liquidity()
        records.append(contentsOf: v2Records)
        
        // 如果支持 V3，获取 V3 流动性
        if config.supportsV3 {
            let v3Records = try await fetchV3Liquidity()
            records.append(contentsOf: v3Records)
        }
        
        return records
    }
}

// MARK: - V2 流动性获取

private extension ChainLiquidityProvider {
    
    func fetchV2Liquidity() async throws -> [ChainLiquidityRecord] {
        guard let receiveAddress = getReceiveAddress() else {
            return []
        }
        
        // 使用 RPC 获取 V2 流动性位置
        let positions = try await rpcService.fetchV2LiquidityPositions(
            user: receiveAddress.eip55,
            blockchainType: config.blockchainType
        )
        
        // 获取代币信息
        let tokens = try fetchTokens(for: positions)
        
        // 构建记录
        var records: [ChainLiquidityRecord] = []
        for position in positions {
            if let record = try await buildV2Record(from: position, tokens: tokens) {
                records.append(record)
            }
        }
        
        return records
    }
    
    func fetchTokens(for positions: [V2LiquidityPosition]) throws -> [MarketKit.Token] {
        var queries: [TokenQuery] = []
        var seen = Set<String>()
        
        for position in positions {
            let token0Address = position.pair.token0.id.lowercased()
            let token1Address = position.pair.token1.id.lowercased()
            
            if !seen.contains(token0Address) {
                seen.insert(token0Address)
                queries.append(TokenQuery(
                    blockchainType: config.blockchainType,
                    tokenType: .eip20(address: position.pair.token0.id)
                ))
            }
            
            if !seen.contains(token1Address) {
                seen.insert(token1Address)
                queries.append(TokenQuery(
                    blockchainType: config.blockchainType,
                    tokenType: .eip20(address: position.pair.token1.id)
                ))
            }
        }
        
        // 添加原生币查询（用于 WETH/WBNB 映射）
        queries.append(TokenQuery(blockchainType: config.blockchainType, tokenType: .native))
        
        return try marketKit.tokens(queries: queries)
    }
    
    func buildV2Record(from position: V2LiquidityPosition, tokens: [MarketKit.Token]) async throws -> ChainLiquidityRecord? {
        let pair = position.pair
        
        // 获取代币
        guard let token0 = resolveToken(from: pair.token0, tokens: tokens),
              let token1 = resolveToken(from: pair.token1, tokens: tokens) else {
            return nil
        }
        
        // 计算用户份额
        let poolInfo = PoolInfo(
            pooltToken0Amount: pair.reserve0BigInt,
            pooltToken1Amount: pair.reserve1BigInt,
            balanceOfAccount: position.liquidityTokenBalanceBigInt,
            poolTokenTotalSupply: pair.totalSupplyBigInt
        )
        
        guard poolInfo.balanceOfAccount > 0 else { return nil }
        
        let token0Amount = Decimal(bigUInt: poolInfo.userToken0Amount, decimals: token0.decimals) ?? 0
        let token1Amount = Decimal(bigUInt: poolInfo.userToken1Amount, decimals: token1.decimals) ?? 0
        let liquidity = Decimal(bigUInt: poolInfo.balanceOfAccount, decimals: 18) ?? 0
        
        return ChainLiquidityRecord(
            id: position.id,
            blockchainType: config.blockchainType,
            poolType: .v2,
            token0: token0,
            token1: token1,
            token0Amount: token0Amount,
            token1Amount: token1Amount,
            liquidity: liquidity,
            shareRate: poolInfo.shareRate,
            pairAddress: pair.id,
            rawData: V2RawData(
                position: position,
                poolInfo: poolInfo,
                token0: token0,
                token1: token1
            )
        )
    }
    
    func resolveToken(from v2Token: V2Token, tokens: [MarketKit.Token]) -> MarketKit.Token? {
        // 首先尝试直接匹配
        if let token = tokens.first(where: {
            $0.blockchainType == config.blockchainType &&
            $0.type == .eip20(address: v2Token.id)
        }) {
            return token
        }
        
        // 尝试映射 WETH/WBNB 到原生币
        if let wethAddress = try? wethAddressString(chain: config.blockchainType),
           v2Token.id.lowercased() == wethAddress.lowercased() {
            return tokens.first { $0.type == .native }
        }
        
        return nil
    }
    
    func wethAddressString(chain: BlockchainType) throws -> String {
        switch chain {
        case .ethereum: return "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
        case .binanceSmartChain: return "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
        case .safe4: return "0x0000000000000000000000000000000000001101"
        default: throw ChainProviderError.unsupportedChain
        }
    }
}

// MARK: - V3 流动性获取

private extension ChainLiquidityProvider {
    
    func fetchV3Liquidity() async throws -> [ChainLiquidityRecord] {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: config.blockchainType).evmKitWrapper else {
            return []
        }
        
        guard let rpcSource = Core.shared.evmSyncSourceManager.httpSyncSource(blockchainType: config.blockchainType)?.rpcSource else {
            return []
        }
        
        let uniswapKit = try! UniswapKit.KitV3.instance(dexType: config.dexType)
        let chain = evmKitWrapper.evmKit.chain
        let owner = evmKitWrapper.evmKit.receiveAddress
        
        // 获取 V3 仓位
        let positions = try await uniswapKit.ownedLiquidity(rpcSource: rpcSource, chain: chain, owner: owner)
        let ownedPositions = positions.filter { $0.liquidity > 0 }
        
        guard !ownedPositions.isEmpty else { return [] }
        
        // 获取代币信息
        let tokens = try fetchV3Tokens(for: ownedPositions)
        
        // 构建记录
        var records: [ChainLiquidityRecord] = []
        for position in ownedPositions {
            if let record = try await buildV3Record(from: position, tokens: tokens, uniswapKit: uniswapKit, rpcSource: rpcSource, chain: chain) {
                records.append(record)
            }
        }
        
        return records
    }
    
    func fetchV3Tokens(for positions: [Positions]) throws -> [MarketKit.Token] {
        var queries: [TokenQuery] = []
        var seen = Set<String>()
        
        for position in positions {
            let token0Address = position.token0.hex.lowercased()
            let token1Address = position.token1.hex.lowercased()
            
            if !seen.contains(token0Address) {
                seen.insert(token0Address)
                queries.append(TokenQuery(
                    blockchainType: config.blockchainType,
                    tokenType: .eip20(address: position.token0.hex)
                ))
            }
            
            if !seen.contains(token1Address) {
                seen.insert(token1Address)
                queries.append(TokenQuery(
                    blockchainType: config.blockchainType,
                    tokenType: .eip20(address: position.token1.hex)
                ))
            }
        }
        
        guard !queries.isEmpty else { return [] }
        return try marketKit.tokens(queries: queries)
    }
    
    func buildV3Record(
        from position: Positions,
        tokens: [MarketKit.Token],
        uniswapKit: UniswapKit.KitV3,
        rpcSource: RpcSource,
        chain: Chain
    ) async throws -> ChainLiquidityRecord? {
        
        // 获取代币
        guard let token0 = tokens.first(where: {
            guard case .eip20(let address) = $0.type else { return false }
            return address.lowercased() == position.token0.hex.lowercased()
        }) else { return nil }
        
        guard let token1 = tokens.first(where: {
            guard case .eip20(let address) = $0.type else { return false }
            return address.lowercased() == position.token1.hex.lowercased()
        }) else { return nil }
        
        // 获取流动性金额
        let (amount0, amount1, _) = try await uniswapKit.getAmountsForLiquidity(
            positions: position,
            rpcSource: rpcSource,
            chain: chain,
            liquidity: position.liquidity
        )
        
        let token0Amount = Decimal(bigUInt: amount0, decimals: token0.decimals) ?? 0
        let token1Amount = Decimal(bigUInt: amount1, decimals: token1.decimals) ?? 0
        let liquidity = Decimal(bigUInt: position.liquidity, decimals: 0) ?? 0
        
        return ChainLiquidityRecord(
            id: "\(position.tokenId)",
            blockchainType: config.blockchainType,
            poolType: .v3,
            token0: token0,
            token1: token1,
            token0Amount: token0Amount,
            token1Amount: token1Amount,
            liquidity: liquidity,
            shareRate: 1.0, // V3 每个仓位是独立的
            pairAddress: position.token0.hex, // V3 使用 token0 地址作为标识
            rawData: V3RawData(
                position: position,
                token0: token0,
                token1: token1,
                uniswapKit: uniswapKit
            )
        )
    }
}

// MARK: - 辅助方法

private extension ChainLiquidityProvider {
    
    func getReceiveAddress() -> EvmKit.Address? {
        guard let activeWallet = walletManager.activeWallets.first(where: {
            $0.token.blockchainType == config.blockchainType
        }) else { return nil }
        
        guard let depositAdapter = adapterManager.depositAdapter(for: activeWallet) else { return nil }
        
        return try? EvmKit.Address(hex: depositAdapter.receiveAddress.address)
    }
}

// MARK: - 原始数据保留

struct V2RawData {
    let position: V2LiquidityPosition
    let poolInfo: PoolInfo
    let token0: MarketKit.Token
    let token1: MarketKit.Token
}

struct V3RawData {
    let position: Positions
    let token0: MarketKit.Token
    let token1: MarketKit.Token
    let uniswapKit: UniswapKit.KitV3
}

// MARK: - PoolInfo

struct PoolInfo {
    let pooltToken0Amount: BigUInt
    let pooltToken1Amount: BigUInt
    let balanceOfAccount: BigUInt
    let poolTokenTotalSupply: BigUInt
    
    var shareRate: Decimal {
        (Decimal(bigUInt: balanceOfAccount, decimals: 0) ?? 0) / 
        (Decimal(bigUInt: poolTokenTotalSupply, decimals: 0) ?? 1)
    }
    
    var userToken0Amount: BigUInt {
        pooltToken0Amount * balanceOfAccount / poolTokenTotalSupply
    }
    
    var userToken1Amount: BigUInt {
        pooltToken1Amount * balanceOfAccount / poolTokenTotalSupply
    }
}

// MARK: - Error

enum ChainProviderError: Error {
    case unsupportedChain
    case noWallet
    case noAdapter
}
