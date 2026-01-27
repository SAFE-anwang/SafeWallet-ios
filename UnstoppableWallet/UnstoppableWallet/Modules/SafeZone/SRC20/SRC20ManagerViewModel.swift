import Combine
import Foundation
import HsExtensions
import MarketKit
import RxSwift
import EvmKit
import BigInt

class SRC20ManagerViewModel: ObservableObject {
    private let disposeBag = DisposeBag()
    private let tokensService: SyncSafe4TokensService
    @Published var viewItems: [ManagerItem] = [ManagerItem]()
    @Published private(set) var dataState: DataStatus<[ManagerItem]> = .loading

    init(tokensService: SyncSafe4TokensService) {
        self.tokensService = tokensService
        
        dataState = .loading
        tokensService.requestTokens()
        
        subscribe(disposeBag, tokensService.dataDriver) { [weak self] in
            let items = $0.map{ token in
                ManagerItem(token: token,
                            canAdditionalIssuance: token.canAdditionalIssuance,
                            canDestroy: token.canDestroy
                )
            }
            DispatchQueue.main.async {
                self?.update(items: items)
            }
            
        }
    }
    
    @MainActor
    func update(items: [ManagerItem]) {
        viewItems = items
        dataState = .completed(items)
    }
    
    class ManagerItem: ObservableObject {
        @Published var token: Safe4CustomTokenRecord
        let canAdditionalIssuance: Bool
        let canDestroy: Bool
        
        var id: String {
            token.name
        }
        
        init(token: Safe4CustomTokenRecord, canAdditionalIssuance: Bool, canDestroy: Bool) {
            self.token = token
            self.canAdditionalIssuance = canAdditionalIssuance
            self.canDestroy = canDestroy
        }
    }
    
    struct DetailViewType: Hashable {
        let editType: SRC20EditType
        let viewModel: AnyObject
        
        static func == (lhs: DetailViewType, rhs: DetailViewType) -> Bool {
            lhs.editType == rhs.editType && lhs.viewModel === rhs.viewModel
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(editType)
            hasher.combine(ObjectIdentifier(viewModel))
        }
    }
}
