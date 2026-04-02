import Combine
import Foundation

class AppViewModel: ObservableObject {
    private let passcodeLockManager = Core.shared.passcodeLockManager
    private let localStorage = Core.shared.localStorage
    private let themeManager = Core.shared.themeManager
    private let accountManager = Core.shared.accountManager
    private var cancellables = Set<AnyCancellable>()
    private var proposalCancellable: AnyCancellable?

    @Published private(set) var passcodeLockState: PasscodeLockState
    @Published private(set) var introVisible: Bool
    @Published private(set) var themeMode: ThemeMode
    @Published private(set) var isShowProposalAlert: Bool = false
    
    init() {
        passcodeLockState = passcodeLockManager.state
        introVisible = !localStorage.mainShownOnce
        themeMode = themeManager.themeMode
        checkProposalUpdate()
        
        passcodeLockManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.passcodeLockState = $0 }
            .store(in: &cancellables)

        themeManager.$themeMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.themeMode = $0 }
            .store(in: &cancellables)
        
        accountManager.activeAccountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] account in
                if let account = account {
                    let delay: TimeInterval = account.backedUp ? 0.5 : 2.5
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self?.checkProposalUpdate()
                    }
                }
            }
            .store(in: &cancellables)
    }
}

extension AppViewModel {
    func handleIntroFinish() {
        localStorage.mainShownOnce = true
        introVisible = false
    }
}

extension AppViewModel {
    func checkProposalUpdate() {
        proposalCancellable = nil
        
        let viewModel = ProposalModule.viewModel(type: .All)
        viewModel.loadNewProposals()
        
        proposalCancellable = viewModel.$hasNewProposal
            .sink { [weak self] hasNewProposal in
                if hasNewProposal {
                    self?.showAlerView(viewModel: viewModel)
                }
            }
    }
    
    private func showAlerView(viewModel: ProposalViewModel) {
        guard Core.shared.accountManager.activeAccount != nil else { return }
        
        Coordinator.shared.present(type: .bottomSheet) { isPresented in
            BottomSheetView(
                items: [
                    .title(icon: nil, title: "提案"),
                    .highlightedDescription(text: "有新的提案,是否查看?", type: .caution, style: .structured),
                    .buttonGroup(.init(buttons: [
                            .init(style: .yellow, title: "查看") {
                                DispatchQueue.main.async {
                                    guard let viewModel = ProposalModule.tabViewModel() else { return }
                                    Coordinator.shared.present { _ in
                                        ProposalTabView(viewModel: viewModel)
                                            .ignoresSafeArea()
                                    }
                                    isPresented.wrappedValue = false
                                }
                            },
                            .init(style: .transparent, title: "不再提醒") {
                                DispatchQueue.main.async {
                                    ProposalStorageManager.saveNeedShowTips(false)
                                    isPresented.wrappedValue = false
                                }
                            }
                        ],
                        alignment: .horizontal)),
                ],
            )
        }
    }
}
