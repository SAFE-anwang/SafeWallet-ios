import Combine
import Foundation
import HdWalletKit
import MarketKit
import RxCocoa
import RxRelay
import RxSwift

class RestorePrivateKeyViewModelNew: ObservableObject {
    private let privateKeyService: RestorePrivateKeyService
    private let service: RestoreService
    private let disposeBag = DisposeBag()

    private let cautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let nameCautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let proceedRelay = PublishRelay<(String, [AccountType], RestoreSelectOptions?)>()

    let defaultAccountName: String
    @Published var name: String = ""
    @Published var text: String = ""
    @Published var textCaution: CautionState = .none
    @Published var nameCaution: CautionState = .none
    @Published var isLoading: Bool = false

    @Published var detectedKeyType: PrivateKeyType = .unsupported
    @Published var availableKeyTypes: [PrivateKeyType] = []
    @Published var selectedKeyType: PrivateKeyType?

    // Password-related properties
    @Published var password: String = ""
    @Published var passwordCaution: CautionState = .none
    @Published var passwordHint: String?
    @Published var requiresPassword: Bool = false
    @Published var passwordErrorCount: Int = 0
    @Published private(set) var restoreSelectOptions: RestoreSelectOptions?
    
    // Input validation and security properties
    @Published var isValidatingInput: Bool = false
    @Published var showSecurityConfirmation: Bool = false
    @Published var inputSource: InputSource = .manual
    @Published var lastScannedText: String = ""
    
    enum InputSource {
        case manual
        case paste
        case scan
    }

    let proceedSubject = PassthroughSubject<(String, [AccountType], RestoreSelectOptions?), Never>()
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

        $password
            .dropFirst()
            .sink { [weak self] newPassword in
                self?.passwordCaution = .none
                self?.privateKeyService.setBip38Password(newPassword)
                // Reset error count when user starts typing new password
                if !newPassword.isEmpty {
                    self?.passwordErrorCount = 0
                }
            }
            .store(in: &cancellables)
    }

    private func detectKeyTypeOnTextChange() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            detectedKeyType = .unsupported
            availableKeyTypes = []
            selectedKeyType = nil
            password = ""
            passwordCaution = .none
            passwordHint = nil
            requiresPassword = false
            passwordErrorCount = 0
            privateKeyService.clearBip38Password()
            return
        }

        detectedKeyType = privateKeyService.detectPrivateKeyType(trimmed)
        var types = privateKeyService.availableKeyTypes(text: trimmed)

        if types.isEmpty, detectedKeyType != .unsupported {
            types = [detectedKeyType]
        } else if detectedKeyType != .unsupported, !types.contains(detectedKeyType) {
            types.insert(detectedKeyType, at: 0)
        }

        availableKeyTypes = types

        if let selectedKeyType, availableKeyTypes.contains(selectedKeyType) {
            self.selectedKeyType = selectedKeyType
        } else if availableKeyTypes.count == 1 {
            selectedKeyType = availableKeyTypes.first
        } else {
            selectedKeyType = nil
        }

        // Handle password field visibility and state
        let newEffectiveType = selectedKeyType ?? detectedKeyType
        let currentRequiresPassword = newEffectiveType == .bitcoinBip38
        
        // Update the published property to trigger UI updates
        requiresPassword = currentRequiresPassword
        
        if currentRequiresPassword {
            passwordHint = "restore.private_key.bip38_password_hint".localized
            if !password.isEmpty {
                privateKeyService.setBip38Password(password)
            }
        } else {
            password = ""
            passwordCaution = .none
            passwordHint = nil
            passwordErrorCount = 0
            privateKeyService.clearBip38Password()
        }
    }
}

extension RestorePrivateKeyViewModelNew {
    var cautionDriver: Driver<Caution?> {
        cautionRelay.asDriver()
    }

    var proceedSignal: Signal<(String, [AccountType], RestoreSelectOptions?)> {
        proceedRelay.asSignal()
    }

    func onChange(text: String) {
        self.text = text
        textCaution = .none
        cautionRelay.accept(nil)
        self.inputSource = .manual
    }
    
    func onPaste(text: String) {
        isValidatingInput = true
        
        // Validate pasted content
        let validationResult = validatePastedContent(text)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isValidatingInput = false
            
            switch validationResult {
            case .success(let cleanedText):
                self.text = cleanedText
                self.inputSource = .paste
                self.textCaution = .none
                self.cautionRelay.accept(nil)
                // Trigger detection after paste
                self.detectKeyTypeOnTextChange()
                
            case .failure(let message):
                self.text = text
                self.inputSource = .paste
                let caution = Caution(text: message, type: .error)
                self.textCaution = .caution(caution)
                self.cautionRelay.accept(caution)
                self.errorSubject.send(message)
            }
        }
    }
    
    func onScan(text: String) {
        isValidatingInput = true
        
        // Validate scanned content
        let validationResult = validateScannedContent(text)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isValidatingInput = false
            
            switch validationResult {
            case .success(let cleanedText):
                self.lastScannedText = cleanedText
                self.text = cleanedText
                self.inputSource = .scan
                self.textCaution = .none
                self.cautionRelay.accept(nil)
                // Show security confirmation for scanned private keys
                self.showSecurityConfirmation = true
                // Trigger detection
                self.detectKeyTypeOnTextChange()
                
            case .failure(let message):
                self.text = text
                self.inputSource = .scan
                let caution = Caution(text: message, type: .error)
                self.textCaution = .caution(caution)
                self.cautionRelay.accept(caution)
                self.errorSubject.send(message)
            }
        }
    }
    
    func confirmScannedInput() {
        showSecurityConfirmation = false
        // Proceed with the scanned input
        detectKeyTypeOnTextChange()
    }
    
    func rejectScannedInput() {
        showSecurityConfirmation = false
        text = ""
        lastScannedText = ""
        clear()
    }
    
    private func validatePastedContent(_ content: String) -> ValidationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for empty content
        guard !trimmed.isEmpty else {
            return .failure(message: "restore.private_key.paste_empty".localized)
        }
        
        // Check for reasonable length (private keys are typically 32-64 characters)
        guard trimmed.count >= 16 else {
            return .failure(message: "restore.private_key.paste_too_short".localized)
        }
        
        // Check for suspicious content (multiple lines, etc.)
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count > 3 {
            return .failure(message: "restore.private_key.paste_multiple_lines".localized)
        }
        
        // Clean the input (remove common prefixes/suffixes that might be copied)
        var cleaned = trimmed
        
        // Remove common prefixes that users might accidentally copy
        let prefixesToRemove = ["Private Key:", "Key:", "Secret:", "Seed:"]
        for prefix in prefixesToRemove {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return .success(cleanedText: cleaned)
    }
    
    private func validateScannedContent(_ content: String) -> ValidationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for empty content
        guard !trimmed.isEmpty else {
            return .failure(message: "restore.private_key.scan_empty".localized)
        }
        
        // Check for reasonable length
        guard trimmed.count >= 16 else {
            return .failure(message: "restore.private_key.scan_too_short".localized)
        }
        
        // QR codes might contain additional data, try to extract just the key
        var cleaned = trimmed
        
        // Handle common QR code formats
        // Format 1: privatekey://<key>
        if cleaned.lowercased().hasPrefix("privatekey://") {
            cleaned = String(cleaned.dropFirst(13))
        }
        // Format 2: key://<key>
        else if cleaned.lowercased().hasPrefix("key://") {
            cleaned = String(cleaned.dropFirst(6))
        }
        
        // Remove any whitespace that might have been introduced by scanning
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "")
        
        return .success(cleanedText: cleaned)
    }
    
    enum ValidationResult {
        case success(cleanedText: String)
        case failure(message: String)
    }

    func onChange(name: String) {
        service.name = name
        self.name = name
        nameCaution = .none
        nameCautionRelay.accept(nil)
    }

    func onSelectKeyType(_ type: PrivateKeyType) {
        selectedKeyType = type

        // Update requiresPassword based on selection
        requiresPassword = (type == .bitcoinBip38)

        if type == .bitcoinBip38 {
            passwordHint = "restore.private_key.bip38_password_hint".localized
            if !password.isEmpty {
                privateKeyService.setBip38Password(password)
            }
        } else {
            password = ""
            passwordCaution = .none
            passwordHint = nil
            passwordErrorCount = 0
            privateKeyService.clearBip38Password()
        }
    }

    func onProceed() {
        guard validateInputs() else {
            return
        }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let accountTypes = self.resolveAccountTypes()
            let accountName = self.resolveAccountName()
            let restoreSelectOptions = self.restoreSelectOptions

            DispatchQueue.main.async {
                self.isLoading = false
                if let accountTypes, !accountTypes.isEmpty {
                    self.proceedSubject.send((accountName, accountTypes, restoreSelectOptions))
                    self.proceedRelay.accept((accountName, accountTypes, restoreSelectOptions))
                }
            }
        }
    }

    private func validateInputs() -> Bool {
        let nameValid = validateName()
        let textValid = validateText()
        let passwordValid = validatePassword()

        return nameValid && textValid && passwordValid
    }

    private func validatePassword() -> Bool {
        guard requiresPassword else {
            return true
        }

        if password.isEmpty {
            let caution = Caution(text: "restore.private_key.password_required".localized, type: .error)
            passwordCaution = .caution(caution)
            return false
        }

        if password.count < 1 {
            let caution = Caution(text: "restore.private_key.password_too_short".localized, type: .error)
            passwordCaution = .caution(caution)
            return false
        }

        passwordCaution = .none
        return true
    }

    private func validateText() -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedText.isEmpty {
            let caution = Caution(text: "restore.private_key.empty_text".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            return false
        }

        if requiresKeyTypeSelection && !canDeferKeyTypeSelection {
            let caution = Caution(text: "restore.private_key.select_format".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            return false
        }

        return true
    }
}

extension RestorePrivateKeyViewModelNew: IRestoreSubViewModel {
    func resolveAccountTypes() -> [AccountType]? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            let caution = Caution(text: "restore.private_key.invalid_key".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            return nil
        }

        do {
            if selectedKeyType == nil, canDeferKeyTypeSelection {
                let accountTypes = try privateKeyService.accountType(text: trimmedText).filter { accountType in
                    switch accountType {
                    case .evmPrivateKey, .trcPrivateKey:
                        return true
                    default:
                        return false
                    }
                }

                guard !accountTypes.isEmpty else {
                    throw RestorePrivateKeyService.RestoreError.invalidPrivateKey
                }

                restoreSelectOptions = nil
                cautionRelay.accept(nil)
                textCaution = .none
                return accountTypes
            }

            let forceType = selectedKeyType
            let accountType = try privateKeyService.accountType(text: trimmedText, forceType: forceType)
            if let context = privateKeyService.wifRoutingContext {
                restoreSelectOptions = RestoreSelectOptions(
                    allowedBlockchainTypes: Set([context.blockchainType]),
                    allowedBitcoinDerivations: context.allowedBitcoinDerivations,
                    autoEnableDefaultTokens: context.skipCoinSelection && !context.requireManualDerivationSelection,
                    blockchainsRequireManualTokenSelection: context.requireManualDerivationSelection ? Set([context.blockchainType]) : nil
                )
            } else if let forceType {
                let isTronPrivateKey = forceType == .tronPrivateKey
                restoreSelectOptions = RestoreSelectOptions(
                    allowedBlockchainTypes: Set(forceType.blockchainTypes),
                    allowedBitcoinDerivations: nil,
                    autoEnableDefaultTokens: isTronPrivateKey ? false : forceType.blockchainTypes.count == 1,
                    blockchainsRequireManualTokenSelection: nil
                )
            } else {
                restoreSelectOptions = nil
            }
            cautionRelay.accept(nil)
            textCaution = .none
            return [accountType]
        } catch let error as RestorePrivateKeyService.RestoreError {
            let errorMessage = self.errorMessage(for: error)
            let caution = Caution(text: errorMessage, type: .error)
            
            // Track password errors for BIP38 decryption failures
            if case .decryptionFailed = error {
                passwordErrorCount += 1
                passwordCaution = .caution(caution)
            } else {
                textCaution = .caution(caution)
            }
            
            cautionRelay.accept(caution)
            errorSubject.send(errorMessage)
            restoreSelectOptions = nil
            return nil
        } catch let error as BitcoinKeyError {
            let errorMessage = errorMessage(for: error)
            let caution = Caution(text: errorMessage, type: .error)
            
            // Track password errors for BIP38 decryption failures
            if case .decryptionFailed = error {
                passwordErrorCount += 1
                passwordCaution = .caution(caution)
            } else {
                textCaution = .caution(caution)
            }
            
            cautionRelay.accept(caution)
            errorSubject.send(errorMessage)
            restoreSelectOptions = nil
            return nil
        } catch {
            let caution = Caution(text: "restore.private_key.invalid_key".localized, type: .error)
            textCaution = .caution(caution)
            cautionRelay.accept(caution)
            errorSubject.send("restore.private_key.invalid_key".localized)
            restoreSelectOptions = nil
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
        password = ""
        passwordCaution = .none
        passwordHint = nil
        requiresPassword = false
        passwordErrorCount = 0
        privateKeyService.clearBip38Password()
        restoreSelectOptions = nil
    }
    
    var passwordErrorWarning: String? {
        guard requiresPassword && passwordErrorCount >= 3 else {
            return nil
        }
        return "restore.private_key.password_error_warning".localized
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
    struct RestoreSelectOptions: Hashable {
        let allowedBlockchainTypes: Set<BlockchainType>?
        let allowedBitcoinDerivations: Set<MnemonicDerivation>?
        let autoEnableDefaultTokens: Bool
        let blockchainsRequireManualTokenSelection: Set<BlockchainType>?
    }
}

extension RestorePrivateKeyViewModelNew {
    var isValid: Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordValid = !requiresPassword || !password.isEmpty
        return !trimmedText.isEmpty && validateName() && passwordValid && (!requiresKeyTypeSelection || canDeferKeyTypeSelection)
    }

    var proceedEnabled: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest4($text, $name, $isLoading, $password)
            .combineLatest($selectedKeyType)
            .map { [weak self] combined, _ in
                guard let self = self else { return false }
                let (text, name, loading, password) = combined
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let passwordValid = !self.requiresPassword || !password.isEmpty
                return !trimmedText.isEmpty && !trimmedName.isEmpty && !loading && passwordValid && (!self.requiresKeyTypeSelection || self.canDeferKeyTypeSelection)
            }
            .eraseToAnyPublisher()
    }

    var detectedKeyTypeName: String {
        title(for: detectedKeyType)
    }

    var shouldShowDetectedKeyType: Bool {
        detectedKeyType != .unsupported && availableKeyTypes.count == 1
    }

    var selectedKeyTypeName: String {
        guard let selectedKeyType else {
            return "button.select".localized
        }

        return title(for: selectedKeyType)
    }

    var shouldShowKeyTypeSelector: Bool {
        availableKeyTypes.count > 1
    }

    var requiresKeyTypeSelection: Bool {
        shouldShowKeyTypeSelector && selectedKeyType == nil
    }

    var canDeferKeyTypeSelection: Bool {
        Set(availableKeyTypes) == Set([.evm, .tronPrivateKey])
    }

    var selectedKeyTypeColorStyle: ColorStyle {
        requiresKeyTypeSelection ? .secondary : .primary
    }

    var keyTypeDescriptions: [String] {
        availableKeyTypes.map(title(for:))
    }

    func title(for type: PrivateKeyType) -> String {
        switch type {
        case .evm:
            return "restore.select_key_type.evm".localized
        case .tronPrivateKey:
            return "restore.select_key_type.trc".localized
        case .hdExtendedKey:
            return "extended_key.bip32_root_key".localized
        case .stellarSecretKey:
            return "stellar_secret_key.title".localized
        case .bitcoinPrivateKey:
            return "Bitcoin Private Key"
        case .bitcoinWif:
            return "Bitcoin WIF"
        case .bitcoinMiniKey:
            return "Bitcoin Mini Key"
        case .bitcoinBrainWallet:
            return "Bitcoin Brain Wallet"
        case .bitcoinBip38:
            return "Bitcoin BIP38"
        case .unsupported:
            return "restore.private_key.invalid_key".localized
        }
    }
}
