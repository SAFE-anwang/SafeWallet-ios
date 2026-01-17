import Combine
import Foundation

class AppViewModel: ObservableObject {
    private let passcodeLockManager = Core.shared.passcodeLockManager
    private let localStorage = Core.shared.localStorage
    private let themeManager = Core.shared.themeManager
    private var cancellables = Set<AnyCancellable>()

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
        let viewModel = ProposalModule.viewModel(type: .All)
        viewModel.loadNewProposals()
        
        viewModel.$hasNewProposal
            .sink { [weak self] hasNewProposal in
                if hasNewProposal {
                    self?.showAlerView()
                }
            }.store(in: &cancellables)
        
    }
    private func showAlerView() {
        Coordinator.shared.present(type: .bottomSheet) { isPresented in
            BottomSheetView(
                icon: .info,
                title: "提案",
                items: [
                    .highlightedDescription(text: "有新的提案,是否查看?", style: .alert),
                ],
                buttons: [
                    .init(style: .yellow, title: "查看") {
                        guard let viewModel = ProposalModule.tabViewModel() else { return }
                        Coordinator.shared.present { _ in
                            ProposalTabView(viewModel: viewModel)
                                .ignoresSafeArea()
                        }
                        isPresented.wrappedValue = false
                    },
                    .init(style: .transparent, title: "不再提醒") {

                        isPresented.wrappedValue = false
                    }
                ],
                isPresented: isPresented
            )
        }
    }
}

