import BigInt
import Foundation
import web3swift

class SafeDappEditViewModel: ObservableObject {
    let info: DAppInfo
    private let service: SafeDappService

    @Published var values: [SafeDappField: String]
    @Published var cautionStates: [SafeDappField: CautionState] = [:]
    @Published var sendState: SafeDappAsyncState = .idle

    init(info: DAppInfo, service: SafeDappService) {
        self.info = info
        self.service = service
        values = [
            .name: info.name,
            .contractAddr: info.contractAddr.address,
            .runUrl: info.runUrl,
            .gitUrl: info.gitUrl,
            .officialUrl: info.officialUrl,
            .officialEmail: info.officialEmail,
            .officialAccount: info.officialAccount.address,
            .description: info.description,
            .keyword: info.keyword,
        ]
    }

    func binding(for field: SafeDappField) -> BindingBox {
        BindingBox(
            get: { self.values[field] ?? "" },
            set: { self.values[field] = $0 }
        )
    }

    func cautionBinding(for field: SafeDappField) -> CautionBindingBox {
        CautionBindingBox(
            get: { self.cautionStates[field] ?? .none },
            set: { self.cautionStates[field] = $0 }
        )
    }

    private func originalValue(for field: SafeDappField) -> String {
        switch field {
        case .name: return info.name
        case .contractAddr: return info.contractAddr.address
        case .runUrl: return info.runUrl
        case .gitUrl: return info.gitUrl
        case .officialUrl: return info.officialUrl
        case .officialEmail: return info.officialEmail
        case .officialAccount: return info.officialAccount.address
        case .description: return info.description
        case .keyword: return info.keyword
        }
    }

    @MainActor
    private func setCaution(_ message: String?, for field: SafeDappField) {
        if let message {
            cautionStates[field] = .caution(Caution(text: message, type: .error))
        } else {
            cautionStates[field] = CautionState.none
        }
    }

    @MainActor
    private func normalizedValue(field: SafeDappField, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let error: String?
        let normalized: String
        switch field {
        case .name:
            error = SafeDappValidation.validateRequired(trimmed, min: 5, max: 50, title: field.title)
            normalized = trimmed
        case .contractAddr:
            if case let .failure(addressError) = SafeDappValidation.ethereumAddress(trimmed, title: field.title) {
                error = addressError.message
                normalized = trimmed
            } else if case let .success(address) = SafeDappValidation.ethereumAddress(trimmed, title: field.title) {
                error = nil
                normalized = address.address
            } else {
                error = nil
                normalized = trimmed
            }
        case .runUrl:
            switch SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200) {
            case let .success(url):
                error = nil
                normalized = url
            case let .failure(urlError):
                error = urlError.message
                normalized = trimmed
            }
        case .gitUrl:
            switch SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 20, max: 200) {
            case let .success(url):
                error = nil
                normalized = url
            case let .failure(urlError):
                error = urlError.message
                normalized = trimmed
            }
        case .officialUrl:
            switch SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200) {
            case let .success(url):
                error = nil
                normalized = url
            case let .failure(urlError):
                error = urlError.message
                normalized = trimmed
            }
        case .officialEmail:
            switch SafeDappValidation.requiredEmail(trimmed, title: field.title) {
            case let .success(email):
                error = nil
                normalized = email
            case let .failure(emailError):
                error = emailError.message
                normalized = trimmed
            }
        case .officialAccount:
            if case let .failure(addressError) = SafeDappValidation.ethereumAddress(trimmed, title: field.title) {
                error = addressError.message
                normalized = trimmed
            } else if case let .success(address) = SafeDappValidation.ethereumAddress(trimmed, title: field.title) {
                error = nil
                normalized = address.address
            } else {
                error = nil
                normalized = trimmed
            }
        case .description:
            error = SafeDappValidation.validateRequired(trimmed, min: 10, max: 1024, title: field.title)
            normalized = trimmed
        case .keyword:
            error = SafeDappValidation.validateOptional(trimmed, min: 0, max: 200, title: field.title)
            normalized = trimmed
        }

        setCaution(error, for: field)
        return error == nil ? normalized : nil
    }

    @MainActor
    func prepareUpdate(field: SafeDappField) -> Bool {
        guard let value = normalizedValue(field: field, value: values[field] ?? "") else {
            sendState = .idle
            return false
        }
        if value == originalValue(for: field).trimmingCharacters(in: .whitespacesAndNewlines) {
            setCaution("safe_dapp.error.unchanged".localized, for: field)
            sendState = .idle
            return false
        }
        values[field] = value
        sendState = .ready
        return true
    }

    func update(field: SafeDappField, onComplete: @escaping (SafeDappAsyncState) -> Void) {
        let rawValue = values[field] ?? ""
        Task {
            guard let value = await normalizedValue(field: field, value: rawValue) else {
                await MainActor.run { onComplete(sendState) }
                return
            }
            if value == originalValue(for: field).trimmingCharacters(in: .whitespacesAndNewlines) {
                await MainActor.run {
                    setCaution("safe_dapp.error.unchanged".localized, for: field)
                    sendState = .idle
                    onComplete(sendState)
                }
                return
            }
            await MainActor.run {
                values[field] = value
                sendState = .sending
            }
            do {
                if [.name, .contractAddr, .runUrl].contains(field), try await service.exists(field: field, value: value) {
                    await MainActor.run {
                        setCaution("safe_dapp.error.value_exists".localized, for: field)
                        sendState = .ready
                        onComplete(sendState)
                    }
                    return
                }
                _ = try await service.update(field: field, id: info.id, value: value)
                await MainActor.run {
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

    struct BindingBox {
        let get: () -> String
        let set: (String) -> Void
    }

    struct CautionBindingBox {
        let get: () -> CautionState
        let set: (CautionState) -> Void
    }
}
