import SwiftUI

struct MarketDappView: View {
    @StateObject var viewModel: MarketDappViewModel
    @State private var loadedTabs = [MarketDappModule.Tab]()

    init(viewModel: MarketDappViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollableTabHeaderView(
                tabs: MarketDappModule.Tab.allCases.map {
                    ScrollableTabHeaderView.Tab(
                        title: $0.title,
                        highlighted: false
                    )
                },
                currentTabIndex: Binding(
                    get: {
                        MarketDappModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                    },
                    set: { index in
                        viewModel.currentTab = MarketDappModule.Tab.allCases[index]
                    }
                ),
                isAequilate: true
            )
            ZStack {
                ForEach(MarketDappModule.Tab.allCases, id: \.id) { tab in
                    MarketDappListView(tab: tab, onOpenUrl: { url in
                        Coordinator.shared.present(url: URL(string: url))
                        stat(page: .vault, event: .open(page: .dapp))
                    })
                    .tag(tab.id)
                    .ignoresSafeArea()
                    .opacity(viewModel.currentTab == tab ? 1 : 0)
                }
            }
        }
        .tint(.themeJacob)
        .navigationTitle("safe_zone.safe4.node.super.title".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

