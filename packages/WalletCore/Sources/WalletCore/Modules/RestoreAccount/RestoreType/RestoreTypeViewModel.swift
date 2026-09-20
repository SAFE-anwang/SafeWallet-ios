
import Combine

class RestoreTypeViewModel: ObservableObject {

    let sourceType: RestoreTypeView.SourceType

    private let showModuleSubject = PassthroughSubject<RestoreTypeModule.RestoreType, Never>()

    init(sourceType: RestoreTypeView.SourceType) {
        self.sourceType = sourceType
    }
}

extension RestoreTypeViewModel {
    var showModulePublisher: AnyPublisher<RestoreTypeModule.RestoreType, Never> {
        showModuleSubject.eraseToAnyPublisher()
    }

    func onTap(type: RestoreTypeModule.RestoreType) {
        switch type {
        case .recoveryOrPrivateKey, .privateKey: showModuleSubject.send(type)
        case .backup: showModuleSubject.send(type)
        }
    }

}

extension RestoreTypeViewModel {
    var items: [RestoreTypeModule.RestoreType] {
        switch sourceType {
        case .wallet: return [.recoveryOrPrivateKey, .privateKey /*, .backup*/]
        case .full: return [/*.backup*/]
        }
    }

    var title: String {
        switch sourceType {
        case .wallet: return "restore.title".localized
        case .full: return "backup_app.restore_type.title".localized
        }
    }

    func title(type: RestoreTypeModule.RestoreType) -> String {
        switch type {
        case .recoveryOrPrivateKey: return "restore_type.recovery.title".localized
        case .privateKey: return "restore_type.recovery.private.title".localized
        case .backup: return "restore_type.backup.title".localized
        }
    }

    func description(type: RestoreTypeModule.RestoreType) -> String {
        switch type {
        case .recoveryOrPrivateKey: return "restore_type.recovery.description".localized
        case .privateKey: return "wallet_select.import_private_key".localized
        case .backup: return "restore_type.backup.description".localized
        }
    }

    func icon(type: RestoreTypeModule.RestoreType) -> String {
        switch type {
        case .recoveryOrPrivateKey: return "edit_24"
        case .privateKey: return "key_24"
        case .backup: return "cloud"
        }
    }
}
