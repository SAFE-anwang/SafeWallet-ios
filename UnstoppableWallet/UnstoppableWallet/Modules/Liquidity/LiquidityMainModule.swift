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

        return ThemeNavigationController(rootViewController: viewController)
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

    enum ApproveStepState: Int {
        case notApproved, revokeRequired, revoking, approveRequired, approving, approved
    }

    class DataSourceState {
        var tokenFrom: Token?
        var tokenTo: Token?
        var amountFrom: Decimal?
        var amountTo: Decimal?
        var exactFrom: Bool

        init(tokenFrom: Token?, tokenTo: Token? = nil, amountFrom: Decimal? = nil, amountTo: Decimal? = nil, exactFrom: Bool = true) {
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

        var provider: Provider {
            didSet {
                if !provider.allowedBlockchainTypes.contains(blockchainType) {
                    blockchainType = provider.allowedBlockchainTypes[0]
                }
            }
        }

        init(blockchainType: BlockchainType, provider: Provider) {
            self.blockchainType = blockchainType
            self.provider = provider
        }

    }

}

extension LiquidityMainModule {

    enum SwapError: Error, Equatable {
        case noBalanceIn
        case insufficientBalanceIn
        case insufficientBalanceOut
        case insufficientAllowance
        case needRevokeAllowance(allowance: CoinValue)

        static func ==(lhs: SwapError, rhs: SwapError) -> Bool {
            switch (lhs, rhs) {
            case (.noBalanceIn, .noBalanceIn): return true
            case (.insufficientBalanceIn, .insufficientBalanceIn): return true
            case (.insufficientBalanceOut, .insufficientBalanceOut): return true
            case (.insufficientAllowance, .insufficientAllowance): return true
            case (.needRevokeAllowance(let lAllowance), .needRevokeAllowance(let rAllowance)): return lAllowance == rAllowance
            default: return false
            }
        }

        var revokeAllowance: CoinValue? {
            switch self {
            case .needRevokeAllowance(let allowance): return allowance
            default: return nil
            }
        }

    }

}

extension BlockchainType {

    var allowedLiquidityProviders: [LiquidityMainModule.Dex.Provider] {
        switch self {
//        case .ethereum: return [.oneInch, .uniswap, .uniswapV3, .safeSwap, .pancakeV3]
        case .binanceSmartChain: return [.pancake]
//        case .polygon: return [.oneInch, .quickSwap, .uniswapV3, .safeSwap]
//        case .avalanche: return [.oneInch]
//        case .optimism: return [.oneInch]
//        case .arbitrumOne: return [.oneInch, .uniswapV3]
//        case .gnosis: return [.oneInch]
//        case .fantom: return [.oneInch]
        default: return []
        }
    }

}

extension LiquidityMainModule.Dex {

    enum Provider: String {
        case pancake = "PancakeSwap"
        
        var allowedBlockchainTypes: [BlockchainType] {
            switch self {
            case .pancake: return [.binanceSmartChain]
            }
        }

        var infoUrl: String {
            switch self {
            case .pancake: return "https://pancakeswap.finance/"
            }
        }

        var title: String {
            switch self {
            case .pancake: return "PancakeSwap"
            }
        }

        var icon: String {
            switch self {
            case .pancake: return "pancake_32"
            }
        }

    }

}

//protocol ISwapErrorProvider {
//    var errors: [Error] { get }
//    var errorsObservable: Observable<[Error]> { get }
//}
