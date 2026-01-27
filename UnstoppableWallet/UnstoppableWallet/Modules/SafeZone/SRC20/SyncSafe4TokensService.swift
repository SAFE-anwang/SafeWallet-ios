import Foundation
import Combine
import RxSwift
import RxCocoa
import RxRelay
import MarketKit
import EvmKit

class SyncSafe4TokensService {
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private var disposeBag = DisposeBag()
    private let storage: Safe4CustomTokenStorage
    private let provider: SyncSafe4TokensProvider
    private let srC20Service: SRC20Service
    private let evmKit: EvmKit.Kit
    private let marketKit: MarketKit.Kit
    private var dataRelay = PublishRelay<[Safe4CustomTokenRecord]>()
    private var isSyncing = false
    
    lazy var cachedRecords: [Safe4CustomTokenRecord] = {
        let records = storage.allTokens().filter{$0.creator.lowercased() == evmKit.receiveAddress.eip55.lowercased()}
        return records
    }()
    
    init(provider: SyncSafe4TokensProvider, srC20Service: SRC20Service, evmKit: EvmKit.Kit, storage: Safe4CustomTokenStorage, marketKit: MarketKit.Kit) {
        self.provider = provider
        self.srC20Service = srC20Service
        self.evmKit = evmKit
        self.storage = storage
        self.marketKit = marketKit
    }
    
    func requestTokens() {
        guard !isSyncing else { return }
        
        Task {
            isSyncing = true
            defer { isSyncing = false }
            
            do{
                let data = try await provider.requestTokens()
                process(data: data)
            }catch{
                // 处理错误
            }
        }
    }
    
    func process(data: Safe4TokensResponse) {
        data.tokens.forEach {
            saveLogo(tokenInfo: $0)
        }
        
        // 处理其他用户的token（已推广的）
        data.tokens
            .filter({$0.creator.lowercased() != evmKit.receiveAddress.eip55.lowercased()})
            .forEach { token in
                if let url = token.logoURI, url.count > 0 { // 已推广
                    addToken(tokenInfo: token)
                }
            }
        
        let userTokens = data.tokens.filter{$0.creator.lowercased() == evmKit.receiveAddress.eip55.lowercased()}
        
        userDefaultsStorage.set(value: userTokens.map{$0.address.lowercased()}, for: Safe4CustomTokenManager.safe4DeployContractsKey)
        
        let userTokenAddresses = Set(userTokens.map{$0.address.lowercased()})
        cachedRecords.forEach { record in
            if !userTokenAddresses.contains(record.address.lowercased()) {
                storage.delete(by: record.address)
            }
        }
        
        userTokens.forEach { token in
            addToken(tokenInfo: token)
            if let url = token.logoURI, !url.isEmpty {
                storage.update(logo: url, address: token.address)
            }
        }
        
        Task {
            do {
                let results = try await requestVersion(tokens: userTokens)
                dataRelay.accept(results.sorted { lhsItem, rhsItem in
                    lhsItem.name.caseInsensitiveCompare(rhsItem.name) == .orderedAscending
                })
            }catch{}
        }
    }
    
    private func requestVersion(tokens: [Safe4CustomTokenRecord]) async throws -> [Safe4CustomTokenRecord] {
        
        guard tokens.count > 0 else { return [] }
        
        var results: [Safe4CustomTokenRecord] = []
        var errors: [Error] = []
        await withTaskGroup(of: Result<Safe4CustomTokenRecord, Error>.self) { taskGroup in
            for token in tokens {
                taskGroup.addTask { [weak self] in
                    do {
                        let record = try self?.storage.asset(address: token.address)
                        if record == nil || record?.version?.count == 0 {
                            if let version = try await self?.srC20Service.version(chainId: token.chainId, contract: token.address) {
                                token.version = version
                                self?.storage.update(token: token)
                            }
                        }
                        return .success(token)

                    }catch{
                        return .failure(SyncRequestError.getVersion)
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
        return results
    }

    private func addToken(tokenInfo: Safe4CustomTokenRecord) {
        let tokenQuery = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: tokenInfo.address))
        
        do{
            let existingToken = try marketKit.token(query: tokenQuery)
            if existingToken == nil {
                let coin = Coin(uid: tokenQuery.customCoinUid, name: tokenInfo.name, code: tokenInfo.symbol)
                try marketKit.insertCoin(coin: coin)
                try marketKit.insertToken(coinUid: tokenQuery.customCoinUid, blockchainUid: BlockchainType.safe4.uid, type: "eip20", decimals: tokenInfo.decimals, reference: tokenInfo.address)
            }
            
            if let existingAsset = try storage.asset(address: tokenInfo.address) {
                if existingAsset != tokenInfo {
                    storage.update(token: tokenInfo)
                }
            } else {
                storage.save(token: tokenInfo)
            }
            
            if  let _ = Core.shared.accountManager.activeAccount {
                let uids = Core.shared.walletManager.activeWallets.map{$0.token.coin.uid.lowercased()}
                if !uids.contains(tokenQuery.customCoinUid.lowercased()) {
                    Core.shared.walletManager.preloadWallets()
                }
            }
        }catch{}
    }
    
    private func saveLogo(tokenInfo: Safe4CustomTokenRecord) {
        let tokenQuery = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: tokenInfo.address))
        if let url = tokenInfo.logoURI {
            userDefaultsStorage.set(value: url, for: tokenQuery.customCoinUid.lowercased())
        }
    }
    
    func logo(coinUid: String) -> String? {
        userDefaultsStorage.value(for: coinUid.lowercased())
    }
    
    var dataDriver: Observable<[Safe4CustomTokenRecord]> {
        dataRelay.asObservable()
    }
    
    enum SyncRequestError: Error {
        case getVersion
    }
}
