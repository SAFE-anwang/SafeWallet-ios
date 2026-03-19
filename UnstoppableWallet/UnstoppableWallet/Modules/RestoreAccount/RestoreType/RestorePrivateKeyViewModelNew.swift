import Combine
import Foundation
import RxCocoa
import RxRelay
import RxSwift

class RestorePrivateKeyViewModelNew: ObservableObject {
    private let privateKeyService: RestorePrivateKeyService
    private let service: RestoreService
    private let disposeBag = DisposeBag()

    private let cautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let nameCautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let proceedRelay = PublishRelay<(String, AccountType)>()

    let defaultAccountName: String
    @Published var name: String = ""
    @Published var text: String = ""
    @Published var textCaution: CautionState = .none
    @Published var nameCaution: CautionState = .none
    @Published var isLoading: Bool = false

    @Published var detectedKeyType: PrivateKeyType = .unsupported
    @Published var showBip38PasswordPrompt: Bool = false
    @Published var bip38Password: String = ""
    @Published var bip38PasswordError: String?

    @Published var availableKeyTypes: [PrivateKeyType] = []
    @Published var selectedKeyType: PrivateKeyType?

    let proceedSubject = PassthroughSubject<(String, AccountType), Never>()
    let errorSubject = PassthroughSubject<String, Never>()

    private var cancellables = Set<AnyCancellable>()

    init(service: RestoreService, privateKeyService: RestorePrivateKeyService) {
        self.service = service
        self.privateKeyService = privateKeyService
        defaultAccountName = service.defaultAccountName
        name = defaultAccountName

        setupBindings()
        detectKeyTypeOnTextChange()
    }

    private func setupBindings() {
        $text
            .dropFirst()
            .sink { [weak self] _ in
                self?.textCaution = .none
                self?.cautionRelay.accept(nil)
                self?.detectKeyTypeOnTextChange()
            }
            .store(in: &cancellables)

        $name
            .dropFirst()
            .sink { [weak self] in
                self?.service.name = $0
                self?.nameCaution = .none
                self?.nameCautionRelay.accept(nil)
            }
            .store(in: &cancellables)

        $bip38Password
            .dropFirst()
            .sink { [weak self] _ in
                self?.bip38PasswordError = nil
            }
            .store(in: &cancellables)
    }

    private func detectKeyTypeOnTextChange() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            detectedKeyType = .unsupported
            availableKeyTypes = []
            selectedKeyType = nil
            showBip38PasswordPrompt = false
            bip38PasswordError = nil
            privateKeyService.clearBip38Password()
            return
        }

        detectedKeyType = privateKeyService.detectPrivateKeyType(trimmed)

        let fallbackTypes: [PrivateKeyType] = [
            .evm, .hdExtendedKey, .stellarSecretKey,
            .bitcoinPrivateKey, .bitcoinWif, .bitcoinMiniKey, .bitcoinBip38, .bitcoinBrainWallet,
        ]

        var types = [PrivateKeyType]()
        if detectedKeyType != .unsupported {
            types.append(detectedKeyType)
        }

        for type in fallbackTypes where !types.contains(type) {
            types.append(type)
        }

        availableKeyTypes = types

        if let selectedKeyType, availableKeyTypes.contains(selectedKeyType) {
            self.selectedKeyType = selectedKeyType
        } else if detectedKeyType != .unsupported {
            selectedKeyType = detectedKeyType
        } else {
            selectedKeyType = availableKeyTypes.first
        }

        if selectedKeyType != .bitcoinBip38 {
            showBip38PasswordPrompt = false
            bip38PasswordError = nil
            privateKeyService.clearBip38Password()
        }
    }
}

extension RestorePrivateKeyViewModelNew {
    var cautionDriver: Driver<Caution?> {
        cautionRelay.asDriver()
    }

    var proceedSignal: Signal<(String, AccountType)> {
        proceedRelay.asSignal()
    }

    func onChange(text: String) {
        self.text = text
        textCaution = .none
        cautionRelay.accept(nil)
    }

    func onChange(name: String) {
        service.name = name
        self.name = name
        nameCaution = .none
        nameCautionRelay.accept(nil)
    }

    func onSelectKeyType(_ type: PrivateKeyType) {
        selectedKeyType = type

        if type == .bitcoinBip38 {
            if bip38Password.isEmpty {
                showBip38PasswordPrompt = true
            } else {
                privateKeyService.setBip38Password(bip38Password)
                showBip38PasswordPrompt = false
            }
        } else {
            showBip38PasswordPrompt = false
            bip38PasswordError = nil
            privateKeyService.clearBip38Password()
        }
    }

    @discardableResult
    func onSubmitBip38Password() -> Bool {
        guard !bip38Password.isEmpty else {
            bip38PasswordError = "restore.private_key.bip38_password_required".localized
            return false
        }

        privateKeyService.setBip38Password(bip38Password)
        showBip38PasswordPrompt = false
        bip38PasswordError = nil
        return true
    }

    func onCancelBip38Password() {
        showBip38PasswordPrompt = false
        bip38PasswordError = nil
    }

    func onProceed() {
        if requiresBip38Password, bip38Password.isEmpty {
            bip38PasswordError = "restore.private_key.bip38_password_required".localized
            showBip38PasswordPrompt = true
            return
        }

        if requiresBip38Password {
            privateKeyService.setBip38Password(bip38Password)
        }

        guard validateInputs() else {
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if let accountType = self.resolveAccountType() {
                let accountName = self.resolveAccountName()

                DispatchQueue.main.async {
                    self.isLoading = false
                    self.proceedSubject.send((accountName, accountType))
                    self.proceedRelay.accept((accountName, accountType))
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }

    private func validateInputs() -> Bool {
        let nameValid = validateName()
        let textValid = validateText()

        return nameValid && textValid
    }

    private func validateText() -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedText.isEmpty {
            let caution = Caution(text: "restore.private_key.empty_text".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            return false
        }

        return true
    }
}

extension RestorePrivateKeyViewModelNew: IRestoreSubViewModel {
    func resolveAccountType() -> AccountType? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            let caution = Caution(text: "restore.private_key.invalid_key".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            return nil
        }

        do {
            let forceType = selectedKeyType
            let accountType = try privateKeyService.accountType(text: trimmedText, forceType: forceType)
            cautionRelay.accept(nil)
            textCaution = .none
            return accountType
        } catch let error as RestorePrivateKeyService.RestoreError {
            let errorMessage = self.errorMessage(for: error)
            let caution = Caution(text: errorMessage, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            errorSubject.send(errorMessage)
            return nil
        } catch let error as BitcoinKeyError {
            let errorMessage = errorMessage(for: error)
            let caution = Caution(text: errorMessage, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            errorSubject.send(errorMessage)
            return nil
        } catch {
            let caution = Caution(text: "restore.private_key.invalid_key".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            errorSubject.send("restore.private_key.invalid_key".localized)
            return nil
        }
    }

    func resolveAccountName() -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? defaultAccountName : trimmedName
    }

    func validateName() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            let caution = Caution(text: "restore.error.empty_name".localized, type: .error)
            nameCaution = .caution(caution)
            nameCautionRelay.accept(caution)
            return false
        }

        if trimmedName.count > 50 {
            let caution = Caution(text: "restore.error.name_too_long".localized, type: .error)
            nameCaution = .caution(caution)
            nameCautionRelay.accept(caution)
            return false
        }

        nameCautionRelay.accept(nil)
        nameCaution = .none
        return true
    }

    func clear() {
        text = ""
        name = defaultAccountName
        textCaution = .none
        nameCaution = .none
        isLoading = false
        cautionRelay.accept(nil)
        nameCautionRelay.accept(nil)
        detectedKeyType = .unsupported
        availableKeyTypes = []
        selectedKeyType = nil
        bip38Password = ""
        bip38PasswordError = nil
        showBip38PasswordPrompt = false
        privateKeyService.clearBip38Password()
    }

    private func errorMessage(for error: RestorePrivateKeyService.RestoreError) -> String {
        switch error {
        case .emptyText:
            return "restore.private_key.empty_text".localized
        case .notSupportedDerivedType:
            return "restore.private_key.not_supported_derived_type".localized
        case .nonPrivateKey:
            return "restore.private_key.non_private_key".localized
        case .noValidKey:
            return "restore.private_key.no_valid_key".localized
        case .unsupportedKeyType:
            return "restore.private_key.unsupported_type".localized
        case .bip38PasswordRequired:
            return "restore.private_key.bip38_password_required".localized
        case .invalidPrivateKey:
            return "restore.private_key.invalid_key".localized
        case .invalidWifChecksum:
            return "restore.private_key.invalid_wif_checksum".localized
        case .invalidBip38Key:
            return "restore.private_key.invalid_bip38_key".localized
        case .decryptionFailed:
            return "restore.private_key.decryption_failed".localized
        }
    }

    private func errorMessage(for error: BitcoinKeyError) -> String {
        switch error {
        case .invalidWifChecksum:
            return "restore.private_key.invalid_wif_checksum".localized
        case .invalidBip38Format, .invalidBip38Checksum, .invalidBip38Key:
            return "restore.private_key.invalid_bip38_key".localized
        case .decryptionFailed:
            return "restore.private_key.decryption_failed".localized
        default:
            return "restore.private_key.invalid_key".localized
        }
    }
}

extension RestorePrivateKeyViewModelNew {
    var isValid: Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty && validateName()
    }

    var proceedEnabled: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest4($text, $name, $isLoading, $showBip38PasswordPrompt)
            .map { text, name, loading, showPrompt in
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmedText.isEmpty && !trimmedName.isEmpty && !loading && !showPrompt
            }
            .eraseToAnyPublisher()
    }

    var detectedKeyTypeName: String {
        detectedKeyType.rawValue
    }

    var keyTypeDescriptions: [String] {
        availableKeyTypes.map { $0.rawValue }
    }

    private var requiresBip38Password: Bool {
        let effectiveType = selectedKeyType ?? detectedKeyType
        return effectiveType == .bitcoinBip38
    }
}
