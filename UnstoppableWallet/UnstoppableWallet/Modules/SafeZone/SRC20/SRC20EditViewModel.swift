import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt

class SRC20EditViewModel: ObservableObject {
    let token: Safe4CustomTokenRecord
    private let type: DeployType
    private let service: SRC20Service
    
    private var whitePaperUrlTemp: String = ""
    private var orgNameTemp: String = ""
    private var officialUrlTemp: String = ""
    private var descriptionTemp: String = ""
    
    @Published var whitePaperUrl: String = ""
    @Published var orgName: String = ""
    @Published var officialUrl: String = ""
    @Published var description: String = ""
    
    @Published var whitePaperUrlCautionState: CautionState = .none
    @Published var orgNameCautionState: CautionState = .none
    @Published var officialUrlCautionState: CautionState = .none
    @Published var descriptionCautionState: CautionState = .none
    @Published var sendState: SendState = .notReady
    @Published var dataState: DataState = .loading
    
    init(token: Safe4CustomTokenRecord, service: SRC20Service) {
        self.token = token
        self.type = token.deployType
        self.service = service
        Task {
            do {
                dataState = .loading
                let whitePaperUrl = try await service.whitePaperUrl(type: type)
                whitePaperUrlTemp = whitePaperUrl
                
                let orgName = try await service.orgName(type: type)
                orgNameTemp = orgName
                
                let officialUrl = try await service.officialUrl(type: type)
                officialUrlTemp = officialUrl
                
                let description = try await service.description(type: type)
                descriptionTemp = description
                
                await MainActor.run { [weak self] in
                    self?.whitePaperUrl = whitePaperUrl
                    self?.orgName = orgName
                    self?.officialUrl = officialUrl
                    self?.description = description
                    self?.dataState = .completed
                }
            }catch{
                await MainActor.run { [weak self] in
                    self?.dataState = .failed
                }
            }
        }
    }
    
    func update(onComplete: @escaping (SendState) -> Void) {
        sendState = .sending
        Task {
            do {
                if whitePaperUrlTemp != whitePaperUrl, !whitePaperUrl.isEmpty {
                    _ = try await service.setWhitePaperUrl(type: type, whitePaperUrl: whitePaperUrl)
                }
                
                if orgNameTemp != orgName, !orgName.isEmpty {
                    _ = try await service.setOrgName(type: type, orgName: orgName)
                }
                
                if officialUrlTemp != officialUrl, !officialUrl.isEmpty {
                    _ = try await service.setOfficialUrl(type: type, officialUrl: officialUrl)

                }
                if descriptionTemp != description, !description.isEmpty {
                    _ = try await service.setDescription(type: type, description: description)
                }
                
                await MainActor.run {[weak self] in
                    self?.sendState = .completed
                    onComplete(.completed)
                }
            }catch{
                await MainActor.run {[weak self] in
                    self?.sendState = .failed
                    onComplete(.failed)
                }
            }
        }
        
    }
    
    var isUpdateAble: Bool {
        (whitePaperUrlTemp != whitePaperUrl && !whitePaperUrl.isEmpty) ||
        (orgNameTemp != orgName && !orgName.isEmpty) ||
        (officialUrlTemp != officialUrl && !officialUrl.isEmpty) ||
        (descriptionTemp != description && !description.isEmpty)
    }
}

extension SRC20EditViewModel {
    enum FocusField: Int, Hashable {
        case whitePaperUrl
        case orgName
        case officialUrl
        case description
    }
    enum DataState: Equatable {
        case loading
        case completed
        case failed
        public static func == (lhs: DataState, rhs: DataState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.completed, .completed): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
    enum SendState: Equatable {
        case notReady
        case ready
        case sending
        case completed
        case failed
        public static func == (lhs: SendState, rhs: SendState) -> Bool {
            switch (lhs, rhs) {
            case (.notReady, .notReady): return true
            case (.ready, .ready): return true
            case (.sending, .sending): return true
            case (.completed, .completed): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
}
