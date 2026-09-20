import Foundation
import HdWalletKit
import MoneroKit
import RxRelay
import RxSwift

class RestoreMnemonicService {
    private let languageManager: LanguageManager
    private let supportsMonero: Bool
    private var wordList: [String] = Mnemonic.wordList(for: .english).map(String.init)
    private let passphraseEnabledRelay = BehaviorRelay<Bool>(value: false)

    private let regex = try! NSRegularExpression(pattern: "\\S+")
    private(set) var items: [WordItem] = []

    private let wordListLanguageRelay = PublishRelay<Mnemonic.Language>()
    private(set) var wordListLanguage: Mnemonic.Language = .english {
        didSet {
            wordListLanguageRelay.accept(wordListLanguage)
        }
    }

    var passphrase: String = ""

    init(languageManager: LanguageManager, supportsMonero: Bool = false) {
        self.languageManager = languageManager
        self.supportsMonero = supportsMonero
    }

    private func language(wordList: Mnemonic.Language) -> String {
        switch wordList {
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .spanish: return "es"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .french: return "fr"
        case .italian: return "it"
        case .czech: return "cs"
        case .portuguese: return "pt"
        }
    }
}

extension RestoreMnemonicService {
    var wordListLanguageObservable: Observable<Mnemonic.Language> {
        wordListLanguageRelay.asObservable()
    }

    var passphraseEnabled: Bool {
        passphraseEnabledRelay.value
    }

    var passphraseEnabledObservable: Observable<Bool> {
        passphraseEnabledRelay.asObservable()
    }

    func displayName(wordList: Mnemonic.Language) -> String {
        languageManager.displayName(language: language(wordList: wordList)) ?? "\(wordList)"
    }

    func set(wordListLanguage: Mnemonic.Language) {
        self.wordListLanguage = wordListLanguage
        wordList = Mnemonic.wordList(for: wordListLanguage).map(String.init)
    }

    func syncItems(text: String) {
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))

        items = matches.compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }

            let word = String(text[range]).lowercased()

            let type: WordItemType

            if wordList.contains(word) || supportsMonero && MoneroMnemonic.isValid(word: word) {
                type = .correct
            } else if wordList.contains(where: { $0.hasPrefix(word) }) || supportsMonero && MoneroMnemonic.isValid(word: word, partial: true) {
                type = .correctPrefix
            } else {
                type = .incorrect
            }

            return WordItem(word: word, range: match.range, type: type)
        }
    }

    func possibleWords(string: String) -> [String] {
        wordList.filter { $0.hasPrefix(string) } + (supportsMonero ? MoneroMnemonic.suggestions(prefix: string) : [])
    }

    func set(passphraseEnabled: Bool) {
        passphraseEnabledRelay.accept(passphraseEnabled)
    }

    func accountType(words: [String]) throws -> AccountType {
        var errors = [Error]()
        let isMoneroMnemonic = supportsMonero && words.count == MoneroMnemonic.wordCount

        if passphraseEnabled, (isMoneroMnemonic ? passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : passphrase.isEmpty) {
            errors.append(RestoreError.emptyPassphrase)
        }

        if isMoneroMnemonic {
            do {
                guard words.allSatisfy({ MoneroMnemonic.isValid(word: $0) }) else {
                    throw RestoreError.invalidMoneroChecksum
                }
                try MoneroMnemonic.validateChecksum(words: words)
            } catch {
                errors.append(RestoreError.invalidMoneroChecksum)
            }
        } else {
            do {
                try Mnemonic.validate(words: words)
            } catch {
                errors.append(error)
            }
        }

        guard errors.isEmpty else {
            throw ErrorList.errors(errors)
        }

        if isMoneroMnemonic {
            return .moneroMnemonic(
                words: words.map(\.decomposedStringWithCompatibilityMapping),
                passphrase: passphraseEnabled ? passphrase : ""
            )
        }

        return .mnemonic(
            words: words.map(\.decomposedStringWithCompatibilityMapping),
            salt: passphrase.decomposedStringWithCompatibilityMapping,
            bip39Compliant: true
        )
    }
}

extension RestoreMnemonicService {
    enum WordItemType {
        case correct
        case incorrect
        case correctPrefix
    }

    struct WordItem {
        let word: String
        let range: NSRange
        let type: WordItemType
    }

    enum RestoreError: Error {
        case emptyPassphrase
        case invalidMoneroChecksum
    }

    enum ErrorList: Error {
        case errors([Error])
    }
}
