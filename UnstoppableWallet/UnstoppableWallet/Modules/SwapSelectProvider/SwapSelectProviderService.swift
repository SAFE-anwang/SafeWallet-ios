import MarketKit
import RxRelay
import RxSwift
import ThemeKit

class SwapSelectProviderService {
    private var dexManager: ISwapDexManager?
    private var liquidityDexManager: ILiquidityDexManager?
    private let evmBlockchainManager: EvmBlockchainManager

    private let itemsRelay = PublishRelay<[Item]>()
    private(set) var items = [Item]() {
        didSet {
            itemsRelay.accept(items)
        }
    }

    init(dexManager: ISwapDexManager, evmBlockchainManager: EvmBlockchainManager) {
        self.dexManager = dexManager
        self.evmBlockchainManager = evmBlockchainManager

        syncItems()
    }
    
    init(dexManager: ILiquidityDexManager, evmBlockchainManager: EvmBlockchainManager) {
        self.liquidityDexManager = dexManager
        self.evmBlockchainManager = evmBlockchainManager

        syncLiquidityItems()
    }
    
    private func syncItems() {
        guard let dex = dexManager?.dex else {
            items = []
            return
        }
        var items = [Item]()

        for provider in dex.blockchainType.allowedProviders {
            items.append(Item(provider: provider, selected: provider == dex.provider))
        }

        self.items = items
    }
}

extension SwapSelectProviderService {
    
    private func syncLiquidityItems() {
        guard let dex = liquidityDexManager?.dex else {
            items = []
            return
        }
        var items = [Item]()

        for provider in dex.blockchainType.allowedLiquidityProviders {
            items.append(Item(provider: provider, selected: provider == dex.provider))
        }

        self.items = items
    }
}

extension SwapSelectProviderService {
    var itemsObservable: Observable<[Item]> {
        itemsRelay.asObservable()
    }

    var blockchain: Blockchain? {
        if let dexManager {
            return dexManager.dex.flatMap { evmBlockchainManager.blockchain(type: $0.blockchainType) }
        }else if let liquidityDexManager {
            return liquidityDexManager.dex.flatMap { evmBlockchainManager.blockchain(type: $0.blockchainType) }
        }else {
            return nil
        }
        
    }

    func set(provider: SwapModule.Dex.Provider) {
        
        if let dexManager {
            dexManager.set(provider: provider)
            syncItems()
        }else if let liquidityDexManager {
            liquidityDexManager.set(provider: provider)
            syncLiquidityItems()
        }

    }
}

extension SwapSelectProviderService {
    struct Item {
        let provider: SwapModule.Dex.Provider
        let selected: Bool
    }
}
