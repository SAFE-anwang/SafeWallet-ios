import Combine
import Foundation

class RestoreViewModel: ObservableObject {
    private let service: RestoreService
    private let mnemonicService: RestoreMnemonicService
    private let walletType: MnemonicRestoreWalletType
    private var cancellables = Set<AnyCancellable>()

    let defaultAccountName: String
    let supportsPassphrase: Bool
    let supportsCustomPath: Bool
    let supportsCustomName: Bool

    @Published var name: String = ""
    @Published var text: String = ""
    @Published var textCaution: CautionState = .none
    @Published var nameCaution: CautionState = .none
    @Published var requirePassword: Bool = false
    @Published var password: String = ""
    @Published var passwordCaution: CautionState = .none
    @Published var selectedWalletName: String = ""
    @Published var selectedWalletBip32Paths: [String] = []
    @Published var currentBip32PathIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var walletNameCaution: CautionState = .none
    @Published var bip32PathCaution: CautionState = .none

    let proceedSubject = PassthroughSubject<(String, AccountType), Never>()
    let errorSubject = PassthroughSubject<String, Never>()

    init(
        walletType: MnemonicRestoreWalletType,
        service: RestoreService = RestoreService(accountFactory: Core.shared.accountFactory),
        mnemonicService: RestoreMnemonicService = RestoreMnemonicService(languageManager: LanguageManager.shared)
    ) {
        self.walletType = walletType
        self.service = service
        self.mnemonicService = mnemonicService
        defaultAccountName = service.defaultAccountName

        supportsPassphrase = walletType.supportsPassphrase
        supportsCustomPath = walletType.supportsCustomPath
        supportsCustomName = walletType.supportsCustomName

        name = defaultAccountName
        requirePassword = false

        setupBindings()
    }

    var allowedBitcoinDerivations: Set<MnemonicDerivation>? {
        let allDerivations = Set(MnemonicDerivation.allCases)
        let supported = Set(walletType.supportedDerivations)
        return supported == allDerivations ? nil : supported
    }

    var proceedEnabled: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest4($text, $requirePassword, $password, $isLoading)
            .combineLatest($selectedWalletName, $selectedWalletBip32Paths)
            .map { combined in
                let (text, requirePassword, password, isLoading) = combined.0
                let walletName = combined.1
                let bip32Paths = combined.2
                let hasMnemonicText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasPassphrase = !requirePassword || !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasWalletName = !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasBip32Path = !bip32Paths.isEmpty
                return hasMnemonicText && hasPassphrase && !isLoading && hasWalletName && hasBip32Path
            }
            .eraseToAnyPublisher()
    }

    func onProceed() {
        textCaution = .none
        passwordCaution = .none
        nameCaution = .none

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            textCaution = .caution(Caution(text: AppError.invalidWords(count: 0).localizedDescription, type: .error))
            return
        }

        isLoading = true

        if let accountType = resolveAccountType() {
            proceedSubject.send((resolvedName, accountType))
        }

        isLoading = false
    }

    private func setupBindings() {
        $text
            .dropFirst()
            .sink { [weak self] _ in
                self?.textCaution = .none
            }
            .store(in: &cancellables)

        $password
            .dropFirst()
            .sink { [weak self] _ in
                self?.passwordCaution = .none
            }
            .store(in: &cancellables)

        $name
            .dropFirst()
            .sink { [weak self] newName in
                self?.service.name = newName
                self?.nameCaution = .none
            }
            .store(in: &cancellables)

        $requirePassword
            .dropFirst()
            .sink { [weak self] isOn in
                guard let self else { return }

                if !isOn || !supportsPassphrase {
                    if !password.isEmpty {
                        password = ""
                    }
                    passwordCaution = .none
                }
            }
            .store(in: &cancellables)

        $selectedWalletName
            .dropFirst()
            .sink { [weak self] _ in
                self?.walletNameCaution = .none
            }
            .store(in: &cancellables)

        $selectedWalletBip32Paths
            .dropFirst()
            .sink { [weak self] _ in
                self?.bip32PathCaution = .none
            }
            .store(in: &cancellables)
    }

    private var resolvedName: String {
        if supportsCustomName {
            return service.resolvedName
        } else {
            return defaultAccountName
        }
    }

    private func resolveAccountType() -> AccountType? {
        mnemonicService.set(passphraseEnabled: supportsPassphrase && requirePassword)
        mnemonicService.passphrase = (supportsPassphrase && requirePassword) ? password : ""
        mnemonicService.syncItems(text: text)

        do {
            let words = mnemonicService.items.map(\.word)
            return try mnemonicService.accountType(words: words)
        } catch let RestoreMnemonicService.ErrorList.errors(errors) {
            for error in errors {
                if case RestoreMnemonicService.RestoreError.emptyPassphrase = error {
                    let message = "restore.error.empty_passphrase".localized
                    passwordCaution = .caution(Caution(text: message, type: .error))
                    errorSubject.send(message)
                } else {
                    let message = error.convertedError.smartDescription
                    textCaution = .caution(Caution(text: message, type: .error))
                    errorSubject.send(message)
                }
            }
            return nil
        } catch {
            let message = error.convertedError.smartDescription
            textCaution = .caution(Caution(text: message, type: .error))
            errorSubject.send(message)
            return nil
        }
    }
}
