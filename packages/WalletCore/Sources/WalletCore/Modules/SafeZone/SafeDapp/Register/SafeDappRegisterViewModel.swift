import Combine
import Foundation

class SafeDappRegisterViewModel: ObservableObject {
    private static let draftKeyPrefix = "safe_dapp.register_draft."
    private let service: SafeDappService
    private var cancellables = Set<AnyCancellable>()

    @Published var form: SafeDappFormData
    @Published var sendState: SafeDappAsyncState = .idle
    @Published var nameCautionState: CautionState = .none
    @Published var contractCautionState: CautionState = .none
    @Published var runUrlCautionState: CautionState = .none
    @Published var descriptionCautionState: CautionState = .none
    @Published var keywordCautionState: CautionState = .none
    @Published var gitUrlCautionState: CautionState = .none
    @Published var officialUrlCautionState: CautionState = .none
    @Published var officialEmailCautionState: CautionState = .none

    init(service: SafeDappService) {
        self.service = service
        form = Self.loadDraft(for: service.account.address) ?? SafeDappFormData()
        $form
            .sink { [weak self] form in
                guard let self else { return }
                self.sendState = .ready
                self.saveDraft(form)
            }
            .store(in: &cancellables)
    }

    private func saveDraft(_ form: SafeDappFormData) {
        let key = Self.draftKey(for: service.account.address)
        if let data = try? JSONEncoder().encode(form) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }

    private static func draftKey(for address: String) -> String {
        "\(draftKeyPrefix)\(address.lowercased())"
    }

    private static func loadDraft(for address: String) -> SafeDappFormData? {
        guard let data = UserDefaults.standard.data(forKey: draftKey(for: address)) else {
            return nil
        }
        return try? JSONDecoder().decode(SafeDappFormData.self, from: data)
    }

    private func removeDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey(for: service.account.address))
        UserDefaults.standard.synchronize()
    }

    @MainActor
    private func clearCautions() {
        nameCautionState = .none
        contractCautionState = .none
        runUrlCautionState = .none
        descriptionCautionState = .none
        keywordCautionState = .none
        gitUrlCautionState = .none
        officialUrlCautionState = .none
        officialEmailCautionState = .none
    }

    @MainActor
    private func setCaution(_ message: String, for field: SafeDappField) {
        let caution = CautionState.caution(Caution(text: message, type: .error))
        switch field {
        case .name: nameCautionState = caution
        case .contractAddr: contractCautionState = caution
        case .runUrl: runUrlCautionState = caution
        case .description: descriptionCautionState = caution
        case .keyword: keywordCautionState = caution
        case .gitUrl: gitUrlCautionState = caution
        case .officialUrl: officialUrlCautionState = caution
        case .officialEmail: officialEmailCautionState = caution
        default: break
        }
    }

    @MainActor
    private func validateLocal() -> Bool {
        clearCautions()
        var isValid = true
        var normalizedForm = form
        normalizedForm.name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedForm.contractAddr = form.contractAddr.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedForm.description = form.description.trimmingCharacters(in: .whitespacesAndNewlines)

        if let error = SafeDappValidation.validateRequired(normalizedForm.name, min: 5, max: 50, title: SafeDappField.name.title) {
            setCaution(error, for: .name)
            isValid = false
        }
        switch SafeDappValidation.ethereumAddress(normalizedForm.contractAddr, title: SafeDappField.contractAddr.title) {
        case let .success(address):
            normalizedForm.contractAddr = address.address
        case let .failure(error):
            setCaution(error.message, for: .contractAddr)
            isValid = false
        }
        switch SafeDappValidation.normalizedUrl(form.runUrl, required: true, title: SafeDappField.runUrl.title, min: 15, max: 200) {
        case let .success(url):
            normalizedForm.runUrl = url
        case let .failure(error):
            setCaution(error.message, for: .runUrl)
            isValid = false
        }
        if let error = SafeDappValidation.validateRequired(normalizedForm.description, min: 10, max: 1024, title: SafeDappField.description.title) {
            setCaution(error, for: .description)
            isValid = false
        }
        switch SafeDappValidation.normalizedKeyword(form.keyword, title: SafeDappField.keyword.title) {
        case let .success(keyword):
            normalizedForm.keyword = keyword
        case let .failure(error):
            setCaution(error.message, for: .keyword)
            isValid = false
        }
        switch SafeDappValidation.normalizedUrl(form.gitUrl, required: false, title: SafeDappField.gitUrl.title, min: 0, max: 200) {
        case let .success(url):
            normalizedForm.gitUrl = url
        case let .failure(error):
            setCaution(error.message, for: .gitUrl)
            isValid = false
        }
        switch SafeDappValidation.normalizedUrl(form.officialUrl, required: false, title: SafeDappField.officialUrl.title, min: 0, max: 200) {
        case let .success(url):
            normalizedForm.officialUrl = url
        case let .failure(error):
            setCaution(error.message, for: .officialUrl)
            isValid = false
        }
        switch SafeDappValidation.optionalEmail(form.officialEmail, title: SafeDappField.officialEmail.title) {
        case let .success(email):
            normalizedForm.officialEmail = email
        case let .failure(error):
            setCaution(error.message, for: .officialEmail)
            isValid = false
        }

        if isValid {
            form = normalizedForm
        }
        sendState = isValid ? .ready : .idle
        return isValid
    }

    @MainActor
    func validateForSubmit() -> Bool {
        validateLocal()
    }

    func register(onComplete: @escaping (SafeDappAsyncState) -> Void) {
        Task {
            guard await validateLocal() else {
                await MainActor.run { onComplete(sendState) }
                return
            }
            await MainActor.run { sendState = .sending }
            do {
                if try await service.exists(field: .name, value: form.name) {
                    await MainActor.run {
                        setCaution("safe_dapp.error.name_exists".localized, for: .name)
                        sendState = .ready
                        onComplete(sendState)
                    }
                    return
                }
                if try await service.exists(field: .contractAddr, value: form.contractAddr) {
                    await MainActor.run {
                        setCaution("safe_dapp.error.contract_exists".localized, for: .contractAddr)
                        sendState = .ready
                        onComplete(sendState)
                    }
                    return
                }
                if try await service.exists(field: .runUrl, value: form.runUrl) {
                    await MainActor.run {
                        setCaution("safe_dapp.error.run_url_exists".localized, for: .runUrl)
                        sendState = .ready
                        onComplete(sendState)
                    }
                    return
                }

                _ = try await service.register(data: form)
                await MainActor.run {
                    removeDraft()
                    sendState = .completed
                    onComplete(sendState)
                }
            } catch {
                await MainActor.run {
                    sendState = .failed(error.localizedDescription)
                    onComplete(sendState)
                }
            }
        }
    }
}
