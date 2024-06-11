import UIKit
import MarketKit
import EvmKit
import SectionsTableView
import ThemeKit
import RxSwift
import RxCocoa

protocol ILiquidityDexManager {
    var dex: LiquidityMainModule.Dex? { get }
    func set(provider: SwapModule.Dex.Provider)

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
    var onOpenSelectProvider: (() -> Void)? { get set }
    var onOpenSettings: (() -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    var onReload: (() -> Void)? { get set }

    func viewDidAppear()
}

enum LiquidityMainModule {

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

    class DataSourceState {
        var tokenFrom: MarketKit.Token?
        var tokenTo: MarketKit.Token?
        var amountFrom: Decimal?
        var amountTo: Decimal?
        var exactFrom: Bool

        init(tokenFrom: MarketKit.Token?, tokenTo: MarketKit.Token? = nil, amountFrom: Decimal? = nil, amountTo: Decimal? = nil, exactFrom: Bool = true) {
            self.tokenFrom = tokenFrom
            self.tokenTo = tokenTo
            self.amountFrom = amountFrom
            self.amountTo = amountTo
            self.exactFrom = exactFrom
        }
    }
    
    class Dex {
        var blockchainType: BlockchainType {
            didSet {
                let allowedProviders = blockchainType.allowedLiquidityProviders
                if !allowedProviders.contains(provider) {
                    provider = allowedProviders[0]
                }
            }
        }

        var provider: SwapModule.Dex.Provider {
            didSet {
                if !provider.allowedBlockchainTypes.contains(blockchainType) {
                    blockchainType = provider.allowedBlockchainTypes[0]
                }
            }
        }

        init(blockchainType: BlockchainType, provider: SwapModule.Dex.Provider) {
            self.blockchainType = blockchainType
            self.provider = provider
        }
    }

}

extension BlockchainType {

    var allowedLiquidityProviders: [SwapModule.Dex.Provider] {
        switch self {
        case .binanceSmartChain: return [.pancake, .pancakeV3]
        case .ethereum: return [.uniswap]//, .uniswapV3]
        default: return []
        }
    }

}

