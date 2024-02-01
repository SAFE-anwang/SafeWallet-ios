import UIKit
import MarketKit
import EvmKit
import SectionsTableView
import ThemeKit
import RxSwift
import RxCocoa

protocol ILiquidityDexManager {
    var dex: LiquidityMainModule.Dex? { get }
    func set(provider: LiquidityMainModule.Dex.Provider)

    var dexUpdated: Signal<()> { get }
}

protocol ILiquidityDataSourceManager {
    var dataSource: ILiquidityDataSource? { get }
    var settingsDataSource: ISwapSettingsDataSource? { get }

    var dataSourceUpdated: Signal<()> { get }
}

protocol ILiquidityProvider: AnyObject {
    var dataSource: ILiquidityDataSource { get }
    var settingsDataSource: ISwapSettingsDataSource? { get }

    var swapState: LiquidityMainModule.DataSourceState { get }
}

protocol ILiquidityDataSource: AnyObject {
    var tableView: UITableView? { get set }
    var buildSections: [SectionProtocol] { get }

    var state: LiquidityMainModule.DataSourceState { get }

    var onOpen: ((_ viewController: UIViewController,_ viaPush: Bool) -> ())? { get set }
    var onOpenSelectProvider: (() -> ())? { get set }
    var onOpenSettings: (() -> ())? { get set }
    var onClose: (() -> ())? { get set }
    var onReload: (() -> ())? { get set }

    func viewDidAppear()
}

class LiquidityMainModule {

    static func viewController(tokenFrom: Token? = nil) -> UIViewController? {
        let swapDexManager = LiquidityProviderMannager(localStorage: App.shared.localStorage, evmBlockchainManager: App.shared.evmBlockchainManager, tokenFrom: tokenFrom)

        let viewModel =  LiquidityMainViewModel(dexManager: swapDexManager)
        let viewController = LiquidityMainViewController(
                viewModel: viewModel,
                dataSourceManager: swapDexManager
        )
        return viewController
    }

}

extension LiquidityMainModule {
    private static let addressesForRevoke = ["0xdac17f958d2ee523a2206206994597c13d831ec7"]

    static func mustBeRevoked(token: Token?) -> Bool {
        if let token = token,
           case .ethereum = token.blockchainType,
           case .eip20(let address) = token.type,
           Self.addressesForRevoke.contains(address.lowercased()) {
            return true
        }

        return false
    }

}

extension LiquidityMainModule {

    class DataSourceState: SwapModule.DataSourceState {
    }

    class Dex: SwapModule.Dex {
        override var blockchainType: BlockchainType {
            didSet {
                let allowedProviders = blockchainType.allowedLiquidityProviders
                if !allowedProviders.contains(provider) {
                    provider = allowedProviders[0]
                }
            }
        }

        override var provider: Provider {
            didSet {
                if !provider.allowedBlockchainTypes.contains(blockchainType) {
                    blockchainType = provider.allowedBlockchainTypes[0]
                }
            }
        }
    }

}

extension BlockchainType {

    var allowedLiquidityProviders: [SwapModule.Dex.Provider] {
        switch self {
        case .binanceSmartChain: return [.pancake]
        case .ethereum: return [.uniswap]
        default: return []
        }
    }

}

