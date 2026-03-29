import Foundation
import HsToolKit
import Alamofire
import MarketKit
import EvmKit
import BigInt

// MARK: - LiquidityRPCService
// 使用 RPC 调用获取流动性数据，替代 Subgraph 方式

class LiquidityRPCService {
    private let networkManager: NetworkManager
    private let retryDelays: [UInt64] = [0, 500_000_000, 1_000_000_000]
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
        
        // 查询每个 LP 代币的详细信息
        var positions = [V2LiquidityPosition]()
        for lpToken in lpTokens {
            do {
                if let position = try await fetchPositionDetail(
                    user: normalizedAddress,
                    pairAddress: lpToken.address,
                    balance: lpToken.balance,
                    blockchainType: blockchainType
                ) {
                    positions.append(position)
                }
            } catch {
                Core.shared.logger.log(
                    level: .warning,
                    message: "Failed to fetch position for \(lpToken.address): \(error.localizedDescription)",
                    context: rpcLogContext,
                    save: true
                )
                continue
            }
        }
        
        return positions
    }
    
    // MARK: - 私有方法
    
    /// 获取用户的 LP 代币列表
    private func fetchLPTokens(user: String, blockchainType: BlockchainType) async throws -> [LPTokenInfo] {
        switch blockchainType {
        case .safe4:
            return try await fetchSafe4LPTokens(user: user)
        case .ethereum, .binanceSmartChain:
            // 对于 ETH/BSC，需要通过事件日志或工厂合约查询
            // 这里简化处理，返回空数组（实际实现需要遍历工厂合约的所有配对）
            return try await fetchEvmLPTokens(user: user, blockchainType: blockchainType)
        default:
            throw RPCError.unsupportedChain
        }
    }
    
    /// 获取 Safe4 的 LP 代币
    private func fetchSafe4LPTokens(user: String) async throws -> [LPTokenInfo] {
        var page = 1
        let pageSize = 100
        var records = [Safe4AddressErc20Record]()
        
        while true {
            let body = Safe4AddressErc20Request(address: user, current: page, pageSize: pageSize)
            let response: Safe4AddressErc20Response = try await safe4ResponseWithRetry(url: safe4AssetsEndpoint(), body: body)
            let data = response.data ?? .empty
            records.append(contentsOf: data.records)
            
            if data.records.count < pageSize || page >= data.totalPages {
                break
            }
            page += 1
        }
        
        return records
            .filter { BigUInt($0.balance) ?? 0 > 0 }
            .map { LPTokenInfo(address: $0.token.lowercased(), balance: $0.balance) }
    }
    
    /// 获取 EVM 链的 LP 代币
    private func fetchEvmLPTokens(user: String, blockchainType: BlockchainType) async throws -> [LPTokenInfo] {
        // 使用事件日志查询用户的 Mint/Burn 事件来获取参与过的配对
        let factoryAddress = try factoryAddress(for: blockchainType)
        let rpcURL = try rpcEndpoint(blockchainType: blockchainType)
        
        // 查询 PairCreated 事件来获取所有配对（简化：只查询最近的事件）
        // 实际生产环境应该使用索引服务或缓存
        var lpTokens: [LPTokenInfo] = []
        
        // 通过常见的 LP 代币合约查询余额
        // 这里我们尝试查询用户持有的所有 ERC20 代币，筛选出可能是 LP 代币的
        // 实际实现应该通过事件日志追踪用户的流动性操作
        
        // 临时方案：查询一些常见的配对（可以根据需求扩展）
        let commonPairs = try await fetchCommonPairs(blockchainType: blockchainType)
        
        for pairAddress in commonPairs {
            do {
                let balance = try await ethCallBalanceOf(
                    contract: pairAddress,
                    userAddress: user,
                    blockchainType: blockchainType
                )
                if balance > 0 {
                    lpTokens.append(LPTokenInfo(address: pairAddress, balance: balance.description))
                }
            } catch {
                continue
            }
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
        let maxPairs = min(Int(pairCount), 1000) // 最多查询 1000 个配对
        var pairs: [String] = []
        
        for index in 0..<maxPairs {
            do {
                let pairAddress = try await ethCallAddressAtIndex(
                    contract: factoryAddress,
                    index: index,
                    blockchainType: blockchainType
                )
                pairs.append(pairAddress)
            } catch {
                continue
            }
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
        
        // 获取代币对信息
        let token0Address = try await ethCallAddress(
            contract: pairAddress,
            methodId: "0x0dfe1681",
            blockchainType: blockchainType
        )
        let token1Address = try await ethCallAddress(
            contract: pairAddress,
            methodId: "0xd21220a7",
            blockchainType: blockchainType
        )
        
        // 获取储备量
        let (reserve0, reserve1) = try await ethCallReserves(
            contract: pairAddress,
            blockchainType: blockchainType
        )
        
        // 获取总供应量
        let totalSupply = try await ethCallUInt(
            contract: pairAddress,
            methodId: "0x18160ddd",
            blockchainType: blockchainType
        )
        
        guard totalSupply > 0 else { return nil }
        
        // 获取代币元数据
        let token0Symbol = (try? await ethCallString(
            contract: token0Address,
            methodId: "0x95d89b41",
            blockchainType: blockchainType
        )) ?? "UNKNOWN"
        let token1Symbol = (try? await ethCallString(
            contract: token1Address,
            methodId: "0x95d89b41",
            blockchainType: blockchainType
        )) ?? "UNKNOWN"
        let token0Decimals = (try? await ethCallUInt(
            contract: token0Address,
            methodId: "0x313ce567",
            blockchainType: blockchainType
        )) ?? 18
        let token1Decimals = (try? await ethCallUInt(
            contract: token1Address,
            methodId: "0x313ce567",
            blockchainType: blockchainType
        )) ?? 18
        
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
    
    private func safe4ResponseWithRetry<T: Encodable, U: Decodable>(url: String, body: T) async throws -> U {
        var lastError: Error?
        
        for (attempt, delay) in retryDelays.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            
            do {
                let request = try buildRequest(url: url, body: body)
                let response: U = try await singleResponse(request: request, as: U.self)
                if let safe4Response = response as? Safe4AddressErc20Response, safe4Response.code != "0" {
                    throw RPCError.safe4ApiError(safe4Response.message)
                }
                return response
            } catch {
                lastError = error
                if attempt < retryDelays.count - 1 && shouldRetry(error: error) {
                    Core.shared.logger.log(
                        level: .warning,
                        message: "Safe4 liquidity query retry \(attempt + 1) failed: \(String(reflecting: error))",
                        context: rpcLogContext,
                        save: true
                    )
                    continue
                }
                throw error
            }
        }
        
        throw lastError ?? RPCError.invalidResponse
    }
    
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
    
    private func buildRequest<T: Encodable>(url: String, body: T) throws -> DataRequest {
        guard let url = URL(string: url) else {
            throw RPCError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return networkManager.session.request(request)
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
    
    private func shouldRetry(error: Error) -> Bool {
        if case let RPCError.safe4ApiError(message) = error, message.contains("系统繁忙") {
            return true
        }
        
        if let afError = error as? AFError {
            if case let .responseValidationFailed(reason) = afError,
               case let .unacceptableStatusCode(code) = reason {
                return [408, 429, 500, 502, 503, 504].contains(code)
            }
            if case let .sessionTaskFailed(underlyingError) = afError,
               let urlError = underlyingError as? URLError {
                return [
                    .timedOut,
                    .cannotFindHost,
                    .cannotConnectToHost,
                    .networkConnectionLost,
                    .dnsLookupFailed,
                    .notConnectedToInternet,
                ].contains(urlError.code)
            }
        }
        
        return false
    }
    
    private func rpcEndpoint(blockchainType: BlockchainType) throws -> String {
        switch blockchainType {
        case .safe4:
            return AppConfig.isSafe4TestNet ? "https://safe4testnet.anwang.com/rpc" : "https://safe4.anwang.com/rpc"
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
    
    private func safe4AssetsEndpoint() -> String {
        AppConfig.isSafe4TestNet ? "https://safe4testnet.anwang.com/5005/assets/addressERC20" : "https://safe4.anwang.com/5005/assets/addressERC20"
    }
}

// MARK: - 数据模型

struct LPTokenInfo {
    let address: String
    let balance: String
}

struct Safe4AddressErc20Request: Encodable {
    let address: String
    let current: Int
    let pageSize: Int
}

struct Safe4AddressErc20Response: Decodable {
    let code: String
    let message: String
    let data: Safe4AddressErc20Page?
}

struct Safe4AddressErc20Page: Decodable {
    let current: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
    let records: [Safe4AddressErc20Record]
    
    static let empty = Safe4AddressErc20Page(current: 1, pageSize: 0, total: 0, totalPages: 0, records: [])
}

struct Safe4AddressErc20Record: Decodable {
    let token: String
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
    case safe4ApiError(String)
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
