import Foundation
import HsToolKit
import Alamofire
import MarketKit
import EvmKit
import BigInt

// MARK: - LiquidityRPCService
// 使用 RPC 调用获取流动性数据，替代 Subgraph 方式

class LiquidityRPCService {
    private let maxConcurrentRequests = 8
    private let networkManager: NetworkManager
    private let rpcLogContext = ["LiquidityRPC"]

    init(networkManager: NetworkManager = NetworkManager()) {
        self.networkManager = networkManager
    }

    // MARK: - V2 流动性获取

    /// 获取 V2 流动性位置（使用 RPC 方式）
    func fetchV2LiquidityPositions(user: String, blockchainType: BlockchainType) async throws -> [V2LiquidityPosition] {
        let normalizedAddress = try normalizedWalletAddress(user: user)

        // 获取用户的 LP 代币列表
        let lpTokens = try await fetchLPTokens(user: normalizedAddress, blockchainType: blockchainType)

        // Query position details in bounded batches. A task for every pair would
        // overload the RPC endpoint when the wallet owns many LP tokens.
        var positions = [V2LiquidityPosition]()
        for batch in lpTokens.chunks(maxConcurrentRequests) {
            let batchPositions = await withTaskGroup(of: V2LiquidityPosition?.self, returning: [V2LiquidityPosition?].self) { group in
                for lpToken in batch {
                    group.addTask {
                        do {
                            return try await self.fetchPositionDetail(
                                user: normalizedAddress,
                                pairAddress: lpToken.address,
                                balance: lpToken.balance,
                                blockchainType: blockchainType
                            )
                        } catch is CancellationError {
                            return nil
                        } catch {
                            Core.shared.logger.log(
                                level: .warning,
                                message: "Failed to fetch position for \(lpToken.address): \(error.localizedDescription)",
                                context: self.rpcLogContext,
                                save: true
                            )
                            return nil
                        }
                    }
                }

                var results = [V2LiquidityPosition?]()
                for await result in group {
                    results.append(result)
                }
                return results
            }
            positions.append(contentsOf: batchPositions.compactMap { $0 })
        }

        return positions
    }

    // MARK: - 私有方法

    /// 获取用户的 LP 代币列表
    private func fetchLPTokens(user: String, blockchainType: BlockchainType) async throws -> [LPTokenInfo] {
        switch blockchainType {
        case .safe4, .ethereum, .binanceSmartChain:
            // Safe4 的 SafeSwap 与其它 V2 DEX 一样，LP 代币就是 Factory 创建的 Pair。
            // 不使用区块浏览器的 addressERC20 接口：该接口在 Safe4 已不可用，且
            // ERC20 资产列表并不能保证包含 LP token。
            return try await fetchEvmLPTokens(user: user, blockchainType: blockchainType)
        default:
            throw RPCError.unsupportedChain
        }
    }

    /// 获取 EVM 链的 LP 代币
    private func fetchEvmLPTokens(user: String, blockchainType: BlockchainType) async throws -> [LPTokenInfo] {
        var lpTokens: [LPTokenInfo] = []
        let commonPairs = try await fetchCommonPairs(blockchainType: blockchainType)

        for batch in commonPairs.chunks(maxConcurrentRequests) {
            let balances = await withTaskGroup(of: LPTokenInfo?.self, returning: [LPTokenInfo?].self) { group in
                for pairAddress in batch {
                    group.addTask {
                        do {
                            let balance = try await self.ethCallBalanceOf(
                                contract: pairAddress,
                                userAddress: user,
                                blockchainType: blockchainType
                            )
                            guard balance > 0 else { return nil }
                            return LPTokenInfo(address: pairAddress, balance: balance.description)
                        } catch is CancellationError {
                            return nil
                        } catch {
                            return nil
                        }
                    }
                }

                var results = [LPTokenInfo?]()
                for await result in group {
                    results.append(result)
                }
                return results
            }
            lpTokens.append(contentsOf: balances.compactMap { $0 })
        }

        return lpTokens
    }

    /// 通过工厂合约获取所有配对地址
    private func fetchCommonPairs(blockchainType: BlockchainType) async throws -> [String] {
        let factoryAddress = try factoryAddress(for: blockchainType)

        // 获取工厂合约的配对数量
        let pairCount = try await ethCallUInt(
            contract: factoryAddress,
            methodId: "0x574f2ba3", // allPairsLength()
            blockchainType: blockchainType
        )

        guard pairCount > 0 else { return [] }

        // 遍历所有配对（限制数量以避免过多 RPC 调用）
        let maxPairs = min(pairCount, BigUInt(1000)) // 最多查询 1000 个配对
        var pairs: [String] = []

        for batchStart in stride(from: 0, to: Int(maxPairs), by: maxConcurrentRequests) {
            let batchEnd = min(batchStart + maxConcurrentRequests, Int(maxPairs))
            let batchPairs = await withTaskGroup(of: String?.self, returning: [String?].self) { group in
                for index in batchStart..<batchEnd {
                    group.addTask {
                        do {
                            return try await self.ethCallAddressAtIndex(
                                contract: factoryAddress,
                                index: index,
                                blockchainType: blockchainType
                            )
                        } catch is CancellationError {
                            return nil
                        } catch {
                            return nil
                        }
                    }
                }

                var results = [String?]()
                for await result in group {
                    results.append(result)
                }
                return results
            }
            pairs.append(contentsOf: batchPairs.compactMap { $0 })
        }

        return pairs
    }

    /// 获取工厂合约中指定索引的配对地址
    private func ethCallAddressAtIndex(contract: String, index: Int, blockchainType: BlockchainType) async throws -> String {
        let methodId = "0x1e3dd18b" // allPairs(uint256)
        let indexHexValue = String(index, radix: 16)
        let indexHex = indexHexValue.paddingLeft(toLength: 64, withPad: "0")
        let data = methodId + indexHex

        let result = try await ethCall(contract: contract, data: data, blockchainType: blockchainType)
        let value = stripHexPrefix(result)
        guard value.count >= 40 else {
            throw RPCError.invalidResponse
        }
        return "0x" + String(value.suffix(40)).lowercased()
    }

    /// 获取工厂合约地址
    private func factoryAddress(for blockchainType: BlockchainType) throws -> String {
        switch blockchainType {
        case .safe4:
            return "0xB3c827077312163c53E3822defE32cAffE574B42" // SafeSwap V2 Factory
        case .ethereum:
            return "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f" // Uniswap V2 Factory
        case .binanceSmartChain:
            return "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73" // PancakeSwap V2 Factory
        default:
            throw RPCError.unsupportedChain
        }
    }

    /// 查询余额
    private func ethCallBalanceOf(contract: String, userAddress: String, blockchainType: BlockchainType) async throws -> BigUInt {
        let methodId = "0x70a08231" // balanceOf(address)
        let addressWithoutPrefix = String(userAddress.lowercased().dropFirst(2))
        let paddedAddress = addressWithoutPrefix.paddingLeft(toLength: 64, withPad: "0")
        let data = methodId + paddedAddress

        let result = try await ethCall(contract: contract, data: data, blockchainType: blockchainType)
        return BigUInt(stripHexPrefix(result), radix: 16) ?? 0
    }

    /// 获取流动性位置详情
    private func fetchPositionDetail(
        user: String,
        pairAddress: String,
        balance: String,
        blockchainType: BlockchainType
    ) async throws -> V2LiquidityPosition? {
        let balanceBigInt = BigUInt(balance) ?? 0
        guard balanceBigInt > 0 else { return nil }

        // Independent pair calls can be issued together, while the batch limit
        // above keeps the total number of in-flight RPC requests bounded.
        async let token0AddressResult = ethCallAddress(
            contract: pairAddress,
            methodId: "0x0dfe1681",
            blockchainType: blockchainType
        )
        async let token1AddressResult = ethCallAddress(
            contract: pairAddress,
            methodId: "0xd21220a7",
            blockchainType: blockchainType
        )
        async let reservesResult = ethCallReserves(
            contract: pairAddress,
            blockchainType: blockchainType
        )
        async let totalSupplyResult = ethCallUInt(
            contract: pairAddress,
            methodId: "0x18160ddd",
            blockchainType: blockchainType
        )

        let (token0Address, token1Address, (reserve0, reserve1), totalSupply) = try await (
            token0AddressResult,
            token1AddressResult,
            reservesResult,
            totalSupplyResult
        )

        guard totalSupply > 0 else { return nil }

        // 获取代币元数据
        async let token0SymbolResult = ethCallString(
            contract: token0Address,
            methodId: "0x95d89b41",
            blockchainType: blockchainType
        )
        async let token1SymbolResult = ethCallString(
            contract: token1Address,
            methodId: "0x95d89b41",
            blockchainType: blockchainType
        )
        async let token0DecimalsResult = ethCallUInt(
            contract: token0Address,
            methodId: "0x313ce567",
            blockchainType: blockchainType
        )
        async let token1DecimalsResult = ethCallUInt(
            contract: token1Address,
            methodId: "0x313ce567",
            blockchainType: blockchainType
        )
        let token0Symbol = (try? await token0SymbolResult) ?? "UNKNOWN"
        let token1Symbol = (try? await token1SymbolResult) ?? "UNKNOWN"
        let token0Decimals = (try? await token0DecimalsResult) ?? 18
        let token1Decimals = (try? await token1DecimalsResult) ?? 18

        return V2LiquidityPosition(
            id: "\(pairAddress)-\(user)",
            liquidityTokenBalance: balance,
            pair: V2Pair(
                id: pairAddress,
                token0: V2Token(id: token0Address, symbol: token0Symbol, decimals: token0Decimals.description),
                token1: V2Token(id: token1Address, symbol: token1Symbol, decimals: token1Decimals.description),
                reserve0: reserve0.description,
                reserve1: reserve1.description,
                totalSupply: totalSupply.description
            )
        )
    }

    // MARK: - RPC 调用方法

    private func ethCallAddress(contract: String, methodId: String, blockchainType: BlockchainType) async throws -> String {
        let result = try await ethCall(contract: contract, data: methodId, blockchainType: blockchainType)
        let value = stripHexPrefix(result)
        guard value.count >= 40 else {
            throw RPCError.invalidResponse
        }
        return "0x" + String(value.suffix(40)).lowercased()
    }

    private func ethCallUInt(contract: String, methodId: String, blockchainType: BlockchainType) async throws -> BigUInt {
        let result = try await ethCall(contract: contract, data: methodId, blockchainType: blockchainType)
        return BigUInt(stripHexPrefix(result), radix: 16) ?? 0
    }

    private func ethCallReserves(contract: String, blockchainType: BlockchainType) async throws -> (BigUInt, BigUInt) {
        let result = try await ethCall(contract: contract, data: "0x0902f1ac", blockchainType: blockchainType)
        let value = stripHexPrefix(result)
        guard value.count >= 128 else {
            throw RPCError.invalidResponse
        }

        let reserve0Hex = String(value.prefix(64))
        let reserve1Hex = String(value.dropFirst(64).prefix(64))

        return (
            BigUInt(reserve0Hex, radix: 16) ?? 0,
            BigUInt(reserve1Hex, radix: 16) ?? 0
        )
    }

    private func ethCallString(contract: String, methodId: String, blockchainType: BlockchainType) async throws -> String {
        let result = try await ethCall(contract: contract, data: methodId, blockchainType: blockchainType)
        let hex = stripHexPrefix(result)

        // 处理动态字符串
        if hex.count == 64 {
            guard let data = Data(hexString: hex) else {
                throw RPCError.invalidResponse
            }
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
            throw RPCError.invalidResponse
        }

        guard hex.count >= 128 else {
            throw RPCError.invalidResponse
        }

        let lengthHex = String(hex.dropFirst(64).prefix(64))
        guard let length = Int(lengthHex, radix: 16), length > 0 else {
            throw RPCError.invalidResponse
        }

        let dataHexStart = 128
        let dataHexLength = length * 2
        guard hex.count >= dataHexStart + dataHexLength else {
            throw RPCError.invalidResponse
        }

        let dataHex = String(hex.dropFirst(dataHexStart).prefix(dataHexLength))
        guard let data = Data(hexString: dataHex),
              let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw RPCError.invalidResponse
        }

        return text
    }

    private func ethCall(contract: String, data: String, blockchainType: BlockchainType) async throws -> String {
        let rpcURL = try rpcEndpoint(blockchainType: blockchainType)

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_call",
            "params": [
                [
                    "to": contract,
                    "data": data,
                ],
                "latest",
            ],
        ]

        let request = try buildRawRequest(url: rpcURL, body: body)
        let response: RpcResponse = try await singleResponse(request: request, as: RpcResponse.self)

        if let error = response.error {
            throw RPCError.rpcError(error.message)
        }

        guard let result = response.result, result != "0x" else {
            throw RPCError.invalidResponse
        }

        return result
    }

    // MARK: - 网络请求

    private func singleResponse<T: Decodable>(request: DataRequest, as type: T.Type) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            request
                .validate(statusCode: 200..<300)
                .responseDecodable(of: T.self) { response in
                    switch response.result {
                    case let .success(value):
                        continuation.resume(returning: value)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
        }
    }

    private func buildRawRequest(url: String, body: [String: Any]) throws -> DataRequest {
        guard let url = URL(string: url) else {
            throw RPCError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return networkManager.session.request(request)
    }

    // MARK: - 辅助方法

    private func normalizedWalletAddress(user: String) throws -> String {
        let normalized = user.lowercased()
        guard normalized.hasPrefix("0x"), normalized.count == 42 else {
            throw RPCError.invalidWalletAddress
        }
        return normalized
    }

    private func stripHexPrefix(_ value: String) -> String {
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            return String(value.dropFirst(2))
        }
        return value
    }

    private func rpcEndpoint(blockchainType: BlockchainType) throws -> String {
        switch blockchainType {
        case .safe4:
            return Safe4Network.currentContext.rpcUrlString
        case .ethereum:
            // 使用 EvmSyncSourceManager 获取 RPC 端点
            guard let rpcSource = Core.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum)?.rpcSource else {
                throw RPCError.missingRPCEndpoint
            }
            // 获取第一个 HTTP URL
            if case .http(let urls, _) = rpcSource {
                return urls.first?.absoluteString ?? "https://ethereum.publicnode.com"
            }
            return "https://ethereum.publicnode.com"
        case .binanceSmartChain:
            guard let rpcSource = Core.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .binanceSmartChain)?.rpcSource else {
                throw RPCError.missingRPCEndpoint
            }
            if case .http(let urls, _) = rpcSource {
                return urls.first?.absoluteString ?? "https://bsc.publicnode.com"
            }
            return "https://bsc.publicnode.com"
        default:
            throw RPCError.unsupportedChain
        }
    }

}

// MARK: - 数据模型

struct LPTokenInfo {
    let address: String
    let balance: String
}

struct RpcResponse: Decodable {
    let result: String?
    let error: RpcError?
}

struct RpcError: Decodable {
    let code: Int?
    let message: String
}

// MARK: - V2 流动性数据模型（保留）

struct V2LiquidityPosition: Decodable {
    let id: String
    let liquidityTokenBalance: String
    let pair: V2Pair

    var liquidityTokenBalanceBigInt: BigUInt {
        BigUInt(liquidityTokenBalance) ?? 0
    }
}

struct V2Pair: Decodable {
    let id: String
    let token0: V2Token
    let token1: V2Token
    let reserve0: String
    let reserve1: String
    let totalSupply: String

    var reserve0BigInt: BigUInt {
        BigUInt(reserve0) ?? 0
    }

    var reserve1BigInt: BigUInt {
        BigUInt(reserve1) ?? 0
    }

    var totalSupplyBigInt: BigUInt {
        BigUInt(totalSupply) ?? 0
    }
}

struct V2Token: Decodable {
    let id: String
    let symbol: String
    let decimals: String

    var decimalsInt: Int {
        Int(decimals) ?? 18
    }
}

// MARK: - Error

enum RPCError: Error {
    case invalidURL
    case unsupportedChain
    case invalidResponse
    case invalidWalletAddress
    case missingRPCEndpoint
    case rpcError(String)
}

extension RPCError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid liquidity service URL"
        case .unsupportedChain:
            return "Liquidity is not supported on this chain"
        case .invalidResponse:
            return "Invalid liquidity service response"
        case .invalidWalletAddress:
            return "Invalid wallet address"
        case .missingRPCEndpoint:
            return "RPC endpoint is unavailable"
        case let .rpcError(message):
            return message
        }
    }
}

// MARK: - String Extension

extension String {
    func paddingLeft(toLength: Int, withPad: String) -> String {
        let padding = toLength - self.count
        if padding > 0 {
            return String(repeating: withPad, count: padding) + self
        }
        return self
    }
}
