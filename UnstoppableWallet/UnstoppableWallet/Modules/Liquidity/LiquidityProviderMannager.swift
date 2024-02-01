import UIKit
import MarketKit
import SectionsTableView
import RxSwift
import RxCocoa
import UniswapKit

class LiquidityProviderMannager {
    private let localStorage: LocalStorage
    private let evmBlockchainManager: EvmBlockchainManager

    private let dataSourceUpdatedRelay = PublishRelay<()>()
    private(set) var dataSourceProvider: ILiquidityProvider? {
        didSet {
            dataSourceUpdatedRelay.accept(())
        }
    }

    private let dexUpdatedRelay = PublishRelay<()>()
    var dex: LiquidityMainModule.Dex? {
        didSet {
            dexUpdatedRelay.accept(())
        }
    }

    init(localStorage: LocalStorage, evmBlockchainManager: EvmBlockchainManager, tokenFrom: MarketKit.Token?) {
        self.localStorage = localStorage
        self.evmBlockchainManager = evmBlockchainManager

        initSectionsDataSource(tokenFrom: tokenFrom)
    }

    private func initSectionsDataSource(tokenFrom: MarketKit.Token?) {
        let blockchainType: BlockchainType

        if let tokenFrom = tokenFrom {
            if let type = evmBlockchainManager.blockchain(token: tokenFrom)?.type {
                blockchainType = type
            } else {
                return
            }
        } else {
            blockchainType = .ethereum
        }

        let dexProvider = localStorage.defaultLiquidityProvider(blockchainType: blockchainType)
        let dex = LiquidityMainModule.Dex(blockchainType: blockchainType, provider: dexProvider)

        dataSourceProvider = provider(dex: dex, tokenFrom: tokenFrom)
        self.dex = dex
    }

    private func provider(dex: LiquidityMainModule.Dex, tokenFrom: MarketKit.Token? = nil) -> ILiquidityProvider? {
        let state = dataSourceProvider?.swapState ?? LiquidityMainModule.DataSourceState(tokenFrom: tokenFrom)

        switch dex.provider {
        case .uniswap, .pancake:
            return PancakeLiquidityModule(dex: dex, dataSourceState: state)
//        case .uniswapV3:
//            return UniswapV3Module(dex: dex, dataSourceState: state, dexType: .uniswap)
//        case .pancakeV3:
//            return UniswapV3Module(dex: dex, dataSourceState: state, dexType: .pancakeSwap)
//        case .oneInch:
//            return OneInchModule(dex: dex, dataSourceState: state)
//        case .safeSwap:
        default: return nil
        }
    }

}

extension LiquidityProviderMannager: ILiquidityDexManager {

    func set(provider: LiquidityMainModule.Dex.Provider) {
        guard provider != dex?.provider else {
            return
        }

        let dex: LiquidityMainModule.Dex
        if let oldDex = self.dex {
            oldDex.provider = provider
            dex = oldDex
        } else {
            let blockchainType = provider.allowedBlockchainTypes[0]
            dex = LiquidityMainModule.Dex(blockchainType: blockchainType, provider: provider)
        }

        self.dex = dex
        localStorage.setDefaultLiquidityProvider(blockchainType: dex.blockchainType, provider: dex.provider)

        dataSourceProvider = self.provider(dex: dex)
    }

    var dexUpdated: Signal<()> {
        dexUpdatedRelay.asSignal()
    }

}

extension LiquidityProviderMannager: ILiquidityDataSourceManager {

    var dataSource: ILiquidityDataSource? {
        dataSourceProvider?.dataSource
    }

    var settingsDataSource: ISwapSettingsDataSource? {
        dataSourceProvider?.settingsDataSource
    }

    var dataSourceUpdated: Signal<()> {
        dataSourceUpdatedRelay.asSignal()
    }

}
