import Combine

// Slice of AccountManager the module depends on
protocol IWCAccountProvider: AnyObject {
    var activeAccount: Account? { get }
    var activeAccountId: String? { get }
    var activeAccountIdPublisher: AnyPublisher<String?, Never> { get }
    var deletedAccountIdPublisher: AnyPublisher<String, Never> { get }
}

extension IWCAccountProvider {
    var activeAccountId: String? { activeAccount?.id }
}

extension AccountManager: IWCAccountProvider {
    var activeAccountId: String? {
        activeAccount.map { ChildWalletBridge.shared.contextAccountId(account: $0) }
    }

    var activeAccountIdPublisher: AnyPublisher<String?, Never> {
        Publishers.Merge(
            activeAccountPublisher.map { _ in () },
            ChildWalletBridge.shared.activeChildWalletChangedPublisher.map { _ in () }
        )
        .map { [weak self] in self?.activeAccountId }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    var deletedAccountIdPublisher: AnyPublisher<String, Never> {
        accountDeletedPublisher.map(\.id).eraseToAnyPublisher()
    }
}
