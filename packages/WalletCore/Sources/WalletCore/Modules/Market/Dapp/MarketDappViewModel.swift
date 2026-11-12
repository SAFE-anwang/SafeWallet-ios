import Foundation
import Combine

class MarketDappViewModel: ObservableObject {
    @Published var currentTab: MarketDappModule.Tab = .ALL
    @Published var safeSearchText: String = ""
    @Published private(set) var listContextID = UUID()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Recreate the lists so ownership from the previous wallet cannot remain visible.
        Publishers.Merge3(
            Core.shared.accountManager.activeAccountPublisher.map { _ in () },
            ChildWalletBridge.shared.activeChildWalletChangedPublisher.map { _ in () },
            NotificationCenter.default.publisher(for: .safe4NetworkDidSwitch).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.listContextID = UUID() }
        .store(in: &cancellables)
    }

    func load() {}
}
