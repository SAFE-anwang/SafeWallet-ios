import Combine
import Dispatch
import Foundation

class TonConnectConnectViewModel: ObservableObject {
    private let parameters: TonConnectParameters
    let manifest: TonConnectManifest
    let returnDeepLink: String?

    private let tonConnectManager = Core.shared.tonConnectManager
    private let accountManager = Core.shared.accountManager
    private let childWalletBridge = ChildWalletBridge.shared
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var eligibleAccounts = [Account]()
    @Published var account: Account?

    private let finishSubject = PassthroughSubject<Void, Never>()

    init(config: TonConnectConfig, returnDeepLink: String?) {
        parameters = config.parameters
        manifest = config.manifest
        self.returnDeepLink = returnDeepLink

        accountManager.activeAccountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        accountManager.accountsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        childWalletBridge.activeChildWalletChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        sync()
    }
}

extension TonConnectConnectViewModel {
    var finishPublisher: AnyPublisher<Void, Never> {
        finishSubject.eraseToAnyPublisher()
    }

    func displayName(account: Account) -> String {
        childWalletBridge.displayName(account: account)
    }

    func connect() {
        guard let account else {
            return
        }

        guard !childWalletBridge.isChildWalletActive(account: account) else {
            sync()
            return
        }

        Task {
            try await tonConnectManager.connect(account: account, parameters: parameters, manifest: manifest)

            await MainActor.run {
                finishSubject.send()
            }
        }
    }

    func rejectConnection() {
        Task {
            try await tonConnectManager.rejectConnection(parameters: parameters)
        }
    }

    private func sync() {
        eligibleAccounts = accountManager.accounts.filter {
            $0.type.supportsTonConnect && !childWalletBridge.isChildWalletActive(account: $0)
        }.sorted {
            childWalletBridge.displayName(account: $0).lowercased() < childWalletBridge.displayName(account: $1).lowercased()
        }

        if let activeAccount = accountManager.activeAccount, eligibleAccounts.contains(activeAccount) {
            account = activeAccount
        } else {
            account = eligibleAccounts.first
        }
    }
}
