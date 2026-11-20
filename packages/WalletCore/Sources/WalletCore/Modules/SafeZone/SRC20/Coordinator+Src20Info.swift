import MarketKit

extension Coordinator {

    func presentSrc20Info(token: Token, page: StatPage, section: StatSection? = nil) {
        present { _ in
            Src20TokenInfoView(provider: Safe4Provider(networkManager: Core.shared.networkManager), token: token)
        }
    }
}
