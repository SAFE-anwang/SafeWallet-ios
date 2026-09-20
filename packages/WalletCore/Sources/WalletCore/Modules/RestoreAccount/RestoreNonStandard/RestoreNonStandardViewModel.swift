import Combine
import Foundation
import HdWalletKit

final class RestoreNonStandardViewModel: ObservableObject {
    private let service: RestoreService
    private let mnemonicService: RestoreMnemonicNonStandardService
    private let accountFactory: AccountFactory
    private var cursorOffset = 0

    @Published var name: String
    @Published var text = ""
    @Published var password = ""
    @Published var requirePassword = false
    @Published var possibleWords: [String] = []
    @Published var invalidRanges: [NSRange] = []
    @Published var wordListLanguage: String
    @Published var textCaution: CautionState = .none
    @Published var passwordCaution: CautionState = .none

    let proceedSubject = PassthroughSubject<(String, AccountType), Never>()
    let errorSubject = PassthroughSubject<String, Never>()
    private let replaceWordSubject = PassthroughSubject<(NSRange, String), Never>()

    init(
        service: RestoreService = RestoreService(accountFactory: Core.shared.accountFactory),
        mnemonicService: RestoreMnemonicNonStandardService = RestoreMnemonicNonStandardService(languageManager: LanguageManager.shared),
        accountFactory: AccountFactory = Core.shared.accountFactory
    ) {
        self.service = service
        self.mnemonicService = mnemonicService
        self.accountFactory = accountFactory
        name = service.defaultAccountName
        wordListLanguage = mnemonicService.displayName(wordList: mnemonicService.wordListLanguage)
    }

    var replaceWordPublisher: AnyPublisher<(NSRange, String), Never> {
        replaceWordSubject.eraseToAnyPublisher()
    }

    var wordListViewItems: [AlertViewItem] {
        Mnemonic.Language.allCases.map { language in
            AlertViewItem(
                text: mnemonicService.displayName(wordList: language),
                selected: language == mnemonicService.wordListLanguage
            )
        }
    }

    func refreshName() {
        name = accountFactory.generatedAccountName
    }

    func onChange(text: String, cursorOffset: Int) {
        self.text = text
        self.cursorOffset = cursorOffset
        mnemonicService.syncItems(text: text)
        textCaution = .none

        let hasCursor: (RestoreMnemonicNonStandardService.WordItem) -> Bool = { item in
            cursorOffset >= item.range.lowerBound && cursorOffset <= item.range.upperBound
        }
        invalidRanges = mnemonicService.items.compactMap { item in
            switch item.type {
            case .correct: return nil
            case .incorrect: return item.range
            case .correctPrefix: return hasCursor(item) ? nil : item.range
            }
        }
        possibleWords = mnemonicService.items.first(where: hasCursor)
            .map { mnemonicService.possibleWords(string: $0.word) } ?? []
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

    func onTogglePassphrase(_ isEnabled: Bool) {
        requirePassword = isEnabled
        password = ""
        passwordCaution = .none
        mnemonicService.set(passphraseEnabled: isEnabled)
    }

    func onChangePassword(_ password: String) {
        self.password = password
        passwordCaution = .none
        mnemonicService.passphrase = password
    }

    func onProceed() {
        mnemonicService.syncItems(text: text)
        textCaution = .none
        passwordCaution = .none

        guard mnemonicService.items.allSatisfy({ $0.type == .correct }) else {
            invalidRanges = mnemonicService.items.filter { $0.type != .correct }.map(\.range)
            return
        }

        mnemonicService.set(passphraseEnabled: requirePassword)
        mnemonicService.passphrase = password
        do {
            let accountType = try mnemonicService.accountType(words: mnemonicService.items.map(\.word))
            service.name = name
            proceedSubject.send((service.resolvedName, accountType))
        } catch let RestoreMnemonicNonStandardService.ErrorList.errors(errors) {
            for error in errors {
                if case RestoreMnemonicNonStandardService.RestoreError.emptyPassphrase = error {
                    let message = "restore.error.empty_passphrase".localized
                    passwordCaution = .caution(Caution(text: message, type: .error))
                    errorSubject.send(message)
                } else {
                    let message = error.convertedError.smartDescription
                    textCaution = .caution(Caution(text: message, type: .error))
                    errorSubject.send(message)
                }
            }
        } catch {
            let message = error.convertedError.smartDescription
            textCaution = .caution(Caution(text: message, type: .error))
            errorSubject.send(message)
        }
    }
}
