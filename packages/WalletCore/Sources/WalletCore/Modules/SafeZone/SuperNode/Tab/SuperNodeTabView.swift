import SwiftUI

struct SuperNodeTabView: View {
    @StateObject var viewModel: SuperNodeTabViewModel
    var allViewController: SuperNodeViewController
    var mineViewController: SuperNodeViewController
    @Binding private var isPresented: Bool

    @MainActor
    init(viewModel: SuperNodeTabViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
        let allViewModel = SuperNodeModule.viewModel(type: .All, evmKit: viewModel.evmKit, privateKey: viewModel.privateKey)
        let mineViewModel = SuperNodeModule.viewModel(type: .Mine, evmKit: viewModel.evmKit, privateKey: viewModel.privateKey)
        allViewController = SuperNodeViewController(viewModel: allViewModel)
        mineViewController = SuperNodeViewController(viewModel: mineViewModel)
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
                TabView(selection: Binding(
                    get: {
                        SuperNodeModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                    },
                    set: { index in
                        viewModel.currentTab = SuperNodeModule.Tab.allCases[index]
                    }
                )) {
                    ForEach(SuperNodeModule.Tab.allCases, id: \.self) { tab in
                        switch tab {
                        case .all:
                            SuperNodeView(viewController: allViewController)
                                .ignoresSafeArea()
                                .tag(tab.rawValue)
                        case .mine:
                            SuperNodeView(viewController: mineViewController)
                                .ignoresSafeArea()
                                .tag(tab.rawValue)
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
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
                    .resizable()
                    .frame(size: 24)
            }
        }
    }
}
