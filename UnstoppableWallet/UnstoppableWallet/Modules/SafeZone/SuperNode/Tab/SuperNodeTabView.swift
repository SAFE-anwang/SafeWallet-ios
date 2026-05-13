import SwiftUI

struct SuperNodeTabView: View {
    @StateObject private var viewModel: SuperNodeTabViewModel
    private var allViewModel: SuperNodeViewModel
    private var mineViewModel: SuperNodeViewModel
    @State private var loadedTabs = [SuperNodeModule.Tab]()
    @Binding private var isPresented: Bool

    init(viewModel: SuperNodeTabViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
        self.allViewModel = SuperNodeModule.viewModel(type: .All, evmKit: viewModel.evmKit, privateKey: viewModel.privateKey)
        self.mineViewModel = SuperNodeModule.viewModel(type: .Mine, evmKit: viewModel.evmKit, privateKey: viewModel.privateKey)
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
                            SuperNodeModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                        },
                        set: { index in
                            viewModel.currentTab = SuperNodeModule.Tab.allCases[index]
                        }
                    ),
                    isAequilate: true
                )
                ZStack {
                    SuperNodeView(viewModel: allViewModel)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .all ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }
                    SuperNodeView(viewModel: mineViewModel)
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
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                isPresented = false
            }) {
                Image("close")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                switch viewModel.nodeType {
                case .masterNode:
                    HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.node.tips.state.master".localized))
                case .superNode:
                    HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.node.tips.state.super".localized))
                case .normal:
                    if let viewModel = SuperNodeRegisterModule.viewModel() {
                        Coordinator.shared.present { _ in
                            SuperNodeRegisterView(viewModel: viewModel)
                                .ignoresSafeArea()
                        }
                    }
                }
            }) {
                Image("safe4_add_2_24")
            }
        }
    }
            
    private func load(tab: SuperNodeModule.Tab) {
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
