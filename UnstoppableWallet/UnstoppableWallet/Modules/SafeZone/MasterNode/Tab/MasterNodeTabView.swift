import SwiftUI

struct MasterNodeTabView: View {
    @StateObject var viewModel: MasterNodeTabViewModel
    var allViewModel: MasterNodeViewModel
    var mineViewModel: MasterNodeViewModel
    @State private var loadedTabs = [MasterNodeModule.Tab]()

    init(viewModel: MasterNodeTabViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        allViewModel = MasterNodeModule.viewModel(type: .All, evmKit: viewModel.evmKit)
        mineViewModel = MasterNodeModule.viewModel(type: .Mine, evmKit: viewModel.evmKit)
    }

    var body: some View {
        ThemeNavigationStack {
            VStack(spacing: 0) {
                ScrollableTabHeaderView(
                    tabs: MasterNodeModule.Tab.allCases.map {
                        ScrollableTabHeaderView.Tab(
                            title: $0.title,
                            highlighted: false
                        )
                    },
                    currentTabIndex: Binding(
                        get: {
                            MasterNodeModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                        },
                        set: { index in
                            viewModel.currentTab = MasterNodeModule.Tab.allCases[index]
                        }
                    ),
                    isAequilate: true
                )
                ZStack {
                    MasterNodeView(viewModel: allViewModel)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .all ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }
                    MasterNodeView(viewModel: mineViewModel).ignoresSafeArea()
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
            .navigationTitle("safe_zone.row.masterNode".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar() }
        }

    }
    @ToolbarContentBuilder func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                switch viewModel.nodeType {
                case .masterNode:
                    HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.node.tips.state.master".localized))
                case .superNode:
                    HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.node.tips.state.super".localized))
                case .normal:
                    if let viewModel = MasterNodeRegisterModule.viewModel() {
                        Coordinator.shared.present { _ in
                            MasterNodeRegisterView(viewModel: viewModel)
                                .ignoresSafeArea()
                        }
                    }
                }
            }) {
                Image("safe4_add_2_24")
            }
        }
    }
            
    private func load(tab: MasterNodeModule.Tab) {
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
