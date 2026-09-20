import Combine
import Foundation
import HdWalletKit

class RestoreViewModelNew: ObservableObject {
    private let service: RestoreService
    private let mnemonicService: RestoreMnemonicService
    private let walletType: MnemonicRestoreWalletType
    private var cancellables = Set<AnyCancellable>()
    private var cursorOffset = 0

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
    @Published var possibleWords: [String] = []
    @Published var invalidRanges: [NSRange] = []
    @Published var wordListLanguage: String = ""
    @Published var advanced = false

    let proceedSubject = PassthroughSubject<(String, AccountType), Never>()
    let errorSubject = PassthroughSubject<String, Never>()
    private let replaceWordSubject = PassthroughSubject<(NSRange, String), Never>()

    init(
        walletType: MnemonicRestoreWalletType,
        service: RestoreService = RestoreService(accountFactory: Core.shared.accountFactory),
        mnemonicService: RestoreMnemonicService = RestoreMnemonicService(languageManager: LanguageManager.shared, supportsMonero: true)
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
        wordListLanguage = mnemonicService.displayName(wordList: .english)

        setupBindings()
    }

    var allowedBitcoinDerivations: Set<MnemonicDerivation>? {
        if supportsCustomPath,
           selectedWalletBip32Paths.indices.contains(currentBip32PathIndex),
           let derivation = WalletItem.mnemonicDerivation(path: selectedWalletBip32Paths[currentBip32PathIndex]) {
            return [derivation]
        }

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
                let customWalletSelectionValid = !self.supportsCustomName || (hasWalletName && hasBip32Path)
                return hasMnemonicText && hasPassphrase && !isLoading && customWalletSelectionValid
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

        mnemonicService.syncItems(text: text)

        if let accountType = resolveAccountType() {
            proceedSubject.send((resolvedName, accountType))
        }

        isLoading = false
    }

    var replaceWordPublisher: AnyPublisher<(NSRange, String), Never> {
        replaceWordSubject.eraseToAnyPublisher()
    }

    var wordListViewItems: [AlertViewItem] {
        Mnemonic.Language.allCases.map { language in
            AlertViewItem(
                text: mnemonicService.displayName(wordList: language),
                selected: mnemonicService.wordListLanguage == language
            )
        }
    }

    func onChange(text: String, cursorOffset: Int) {
        self.text = text
        self.cursorOffset = cursorOffset
        mnemonicService.syncItems(text: text)

        let items = mnemonicService.items
        let hasCursor: (RestoreMnemonicService.WordItem) -> Bool = { item in
            cursorOffset >= item.range.lowerBound && cursorOffset <= item.range.upperBound
        }
        invalidRanges = items.compactMap { item in
            switch item.type {
            case .correct: return nil
            case .incorrect: return item.range
            case .correctPrefix: return hasCursor(item) ? nil : item.range
            }
        }
        if let item = items.first(where: hasCursor) {
            possibleWords = mnemonicService.possibleWords(string: item.word)
        } else {
            possibleWords = []
        }
        textCaution = .none
    }

    func onSelect(word: String) {
        guard let item = mnemonicService.items.first(where: { cursorOffset >= $0.range.lowerBound && cursorOffset <= $0.range.upperBound }) else { return }
        replaceWordSubject.send((item.range, word))
    }

    func onSelectWordList(index: Int) {
        let language = Mnemonic.Language.allCases[index]
        mnemonicService.set(wordListLanguage: language)
        wordListLanguage = mnemonicService.displayName(wordList: language)
        onChange(text: text, cursorOffset: text.utf16.count)
    }

    func onToggleAdvanced(_ isEnabled: Bool) {
        advanced = isEnabled
        guard !isEnabled else { return }

        requirePassword = false
        password = ""
        passwordCaution = .none
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
                } else if case RestoreMnemonicService.RestoreError.invalidMoneroChecksum = error {
                    let message = "restore.checksum_error".localized
                    textCaution = .caution(Caution(text: message, type: .error))
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
