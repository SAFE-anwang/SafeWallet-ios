
import UIKit

enum RestoreModule {
    static func viewController(
        advanced: Bool = false,
        initialRestoreType: RestoreViewModel.RestoreType = .mnemonic,
        onRestore: @escaping () -> Void
    ) -> UIViewController {
        let mnemonicService = RestoreMnemonicService(languageManager: LanguageManager.shared)
        let mnemonicViewModel = RestoreMnemonicViewModel(service: mnemonicService)

        let privateKeyService = RestorePrivateKeyService()
        let privateKeyViewModel = RestorePrivateKeyViewModel(service: privateKeyService)

        let service = RestoreService(accountFactory: Core.shared.accountFactory)
        let viewModel = RestoreViewModel(
            service: service,
            mnemonicViewModel: mnemonicViewModel,
            privateKeyViewModel: privateKeyViewModel,
            initialRestoreType: initialRestoreType
        )

        let viewController = RestoreViewController(
            advanced: advanced,
            viewModel: viewModel,
            mnemonicViewModel: mnemonicViewModel,
            privateKeyViewModel: privateKeyViewModel,
            onRestore: onRestore
        )

        return viewController
    }
}
