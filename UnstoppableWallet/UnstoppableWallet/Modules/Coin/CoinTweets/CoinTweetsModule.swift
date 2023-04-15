import MarketKit

struct CoinTweetsModule {

    static func viewController(fullCoin: FullCoin) -> CoinTweetsViewController {
        let tweetsProvider = TweetsProvider(
                networkManager: App.shared.networkManager,
                bearerToken: App.shared.appConfigProvider.twitterBearerToken
        )

        let service = CoinTweetsService(
                coinUid: fullCoin.coin.uid,
                twitterProvider: tweetsProvider,
                marketKit: App.shared.marketKit
        )

        let viewModel = CoinTweetsViewModel(service: service)

        return CoinTweetsViewController(
                viewModel: viewModel,
                urlManager: UrlManager(inApp: true)
        )
    }
    
    static func viewController(username: String) -> CoinTweetsViewController {
        let tweetsProvider = TweetsProvider(
                networkManager: App.shared.networkManager,
                bearerToken: App.shared.appConfigProvider.twitterBearerToken
        )

        let service = CoinTweetsService(
                userName: username,
                twitterProvider: tweetsProvider,
                marketKit: App.shared.marketKit
        )

        let viewModel = CoinTweetsViewModel(service: service)

        return CoinTweetsViewController(
                viewModel: viewModel,
                urlManager: UrlManager(inApp: true)
        )
    }

}
