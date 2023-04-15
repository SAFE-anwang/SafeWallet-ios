
struct MarketTwiitterModule {
    static func viewController() -> MarketTwiitterViewController {
        let service = MarketTwiitterService(marketKit: App.shared.marketKit)
        let viewModel = MarketTwiitterViewModel(service: service)
        return MarketTwiitterViewController(viewModel: viewModel, urlManager: UrlManager(inApp: true))
    }
}
