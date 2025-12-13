import SwiftUI

struct ProposalTabView: View {
    @StateObject var viewModel: ProposalTabViewModel
    private var allViewModel: ProposalViewModel
    private var mineViewModel: ProposalViewModel
    @State private var loadedTabs = [ProposalModule.Tab]()

    init(viewModel: ProposalTabViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        allViewModel = ProposalModule.viewModel(type: .All)
        mineViewModel = ProposalModule.viewModel(type: .Mine(address: viewModel.evmKit.receiveAddress.hex))
    }

    var body: some View {
        ThemeNavigationStack {
            VStack(spacing: 0) {
                ScrollableTabHeaderView(
                    tabs: SuperNodeModule.Tab.allCases.map {
                        ScrollableTabHeaderView.Tab(
                            title: $0.title,
                            highlighted: false
                        )
                    },
                    currentTabIndex: Binding(
                        get: {
                            ProposalModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                        },
                        set: { index in
                            viewModel.currentTab = ProposalModule.Tab.allCases[index]
                        }
                    ),
                    isAequilate: true
                )
                ZStack {
                    ProposalView(viewModel: allViewModel)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .all ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }
                    ProposalView(viewModel: mineViewModel)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .mine ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }
                }
            }
            .tint(.themeJacob)
            .navigationTitle("safe_zone.safe4.node.super.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar() }
        }

    }
    @ToolbarContentBuilder func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                guard viewModel.isEnabledAdd else {
                    HudHelper.instance.show(banner: .error(string: "无法创建，需区块高度大于86400".localized))
                    return
                }
                let viewModel = ProposalCreateModule.viewModel(privateKey: viewModel.privateKey)
                Coordinator.shared.present { _ in
                    ProposalCreateView(viewModel: viewModel)
                        .ignoresSafeArea()
                }
            }) {
                Image("safe4_add_2_24")
            }
        }
    }
            
    private func load(tab: ProposalModule.Tab) {
        guard !loadedTabs.contains(tab) else {
            return
        }

        loadedTabs.append(tab)

        switch tab {
        case .all: allViewModel.refresh()
        case .mine: mineViewModel.refresh()
        }
    }
}

