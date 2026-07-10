import Combine
import MarketKit

class AccountTypeSelectViewModel {
    let items: [ViewItem]

    private let openSelectCoinsSubject = PassthroughSubject<AccountType, Never>()

    init(accountName: String, accountTypes: [AccountType]) {
        items = accountTypes.compactMap { type in
            Self.viewItem(accountType: type)
        }
    }

    private static func viewItem(accountType: AccountType) -> ViewItem? {
        switch accountType {
        case .evmPrivateKey:
            return .init(title: "restore.select_key_type.evm".localized, description: "restore.select_key_type.evm.description".localized, accountType: accountType)
        case .trcPrivateKey:
            return .init(title: "restore.select_key_type.trc".localized, description: "restore.select_key_type.trc.description".localized, accountType: accountType)
        default: return nil
        }
    }

    func onTap(index: Int) {
        guard let item = items.at(index: index) else { return }

        switch item.accountType {
        case .evmPrivateKey, .trcPrivateKey: openSelectCoinsSubject.send(item.accountType)
        default: ()
        }
    }
}

extension AccountTypeSelectViewModel {
    var openSelectCoinsPublisher: AnyPublisher<AccountType, Never> {
        openSelectCoinsSubject.eraseToAnyPublisher()
    }
}

extension AccountTypeSelectViewModel {
    struct ViewItem {
        let title: String
        let description: String
        let accountType: AccountType
    }
}
