import SwiftUI
import WalletCore

@main
struct UnstoppableApp: App {
    @UIApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            switch appDelegate.initResult {
            case .success?:
                AppView()
            case let .failure(error)?:
                LaunchErrorView(error: error)
            case nil:
                EmptyView()
            }
        }
    }

    static func initCore() throws {
        SwapProviderFactory.register([SwapProviderResolver.self])

        // .tonConnect is not registered: TonConnectEventHandler is disabled, a parsed link would
        // only die in the handler chain. Register it together with re-enabling the handler.
        // Open Crypto Pay is retained in WalletCore for future upstream merges, but its app entry
        // points stay disabled in this build.
        [DeepLinkRoute.walletConnect, .tonTransfer, .coin, .referral, .transfer]
            .forEach { DeepLinkRouteFactory.register($0) }
        [AppEventHandlerKind.walletConnect, .widgetCoin, .address, .telegramUser]
            .forEach { AppEventHandlerFactory.register($0) }
        DeepLinkPresenterFactory.register(sendPresenter: DeepLinkPresenterFactory.sendPresenter)

        // Registered BEFORE Core.initApp: adapters/kits are created asynchronously on wallet events, and their
        // factories fatalError on a missing provider — registration must deterministically precede any creation.
        EvmKitConfigFactory.register(UnstoppableEvmKitConfigProvider.self)
        EvmTransactionConverterFactory.register(UnstoppableEvmTransactionConverterProvider.self)

        try Core.initApp(config: Core.Config())

        Core.shared.appManager.didFinishLaunching()
    }
}
