import BigInt
import Foundation
import UIKit
import web3swift

class SafeDappEditViewModel: ObservableObject {
    let info: DAppInfo
    let currentLogo: UIImage?
    private let service: SafeDappService

    @Published var values: [SafeDappField: String]
    @Published var cautionStates: [SafeDappField: CautionState] = [:]
    @Published var sendState: SafeDappAsyncState = .idle

    init(info: DAppInfo, currentLogo: UIImage? = nil, service: SafeDappService) {
        self.info = info
        self.currentLogo = currentLogo
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

    var hasChanges: Bool {
        SafeDappField.editableFields.contains { field in
            normalizedValueWithoutCaution(field: field, value: values[field] ?? "") != originalValue(for: field)
        }
    }

    func binding(for field: SafeDappField) -> BindingBox {
        BindingBox(
            get: { self.values[field] ?? "" },
            set: { self.values[field] = field.truncatedInput($0) }
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

    private func normalizedValueWithoutCaution(field: SafeDappField, value: String) -> String {
        switch field {
        case .contractAddr, .officialAccount:
            return (try? SafeDappValidation.ethereumAddress(value, title: field.title).get().address) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .runUrl, .gitUrl, .officialUrl:
            return (try? SafeDappValidation.normalizedUrl(value, required: field != .gitUrl && field != .officialUrl, title: field.title, min: field == .gitUrl || field == .officialUrl ? 0 : 15, max: 200).get()) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
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
            switch SafeDappValidation.normalizedUrl(trimmed, required: false, title: field.title, min: 0, max: 200) {
            case let .success(url):
                error = nil
                normalized = url
            case let .failure(urlError):
                error = urlError.message
                normalized = trimmed
            }
        case .officialUrl:
            switch SafeDappValidation.normalizedUrl(trimmed, required: false, title: field.title, min: 0, max: 200) {
            case let .success(url):
                error = nil
                normalized = url
            case let .failure(urlError):
                error = urlError.message
                normalized = trimmed
            }
        case .officialEmail:
            switch SafeDappValidation.optionalEmail(trimmed, title: field.title) {
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
    func validateForSubmit() -> Bool {
        var valid = true
        for field in SafeDappField.editableFields {
            guard let normalized = normalizedValue(field: field, value: values[field] ?? "") else {
                valid = false
                continue
            }
            values[field] = normalized
        }
        sendState = valid && hasChanges ? .ready : .idle
        return valid && hasChanges
    }

    func update(onComplete: @escaping (SafeDappAsyncState) -> Void) {
        Task { @MainActor in
            guard validateForSubmit() else {
                onComplete(sendState)
                return
            }
            let changedFields = SafeDappField.editableFields.filter {
                values[$0] != originalValue(for: $0)
            }
            sendState = .sending
            do {
                for field in changedFields {
                    let value = values[field] ?? ""
                    if [.name, .contractAddr, .runUrl].contains(field), try await service.exists(field: field, value: value) {
                        setCaution("safe_dapp.error.value_exists".localized, for: field)
                        sendState = .ready
                        onComplete(sendState)
                        return
                    }
                    _ = try await service.update(field: field, id: info.id, value: value)
                }
                sendState = .completed
                onComplete(sendState)
            } catch {
                sendState = .failed(error.localizedDescription)
                onComplete(sendState)
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
