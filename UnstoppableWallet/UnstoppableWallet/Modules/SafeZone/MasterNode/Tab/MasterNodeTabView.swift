import SwiftUI

struct MasterNodeTabView: View {
    @StateObject var viewModel: MasterNodeTabViewModel
    var allViewController: MasterNodeViewController
    var mineViewController: MasterNodeViewController
    @State private var loadedTabs = [MasterNodeModule.Tab]()
    @Binding private var isPresented: Bool

    init(viewModel: MasterNodeTabViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
        let allViewModel = MasterNodeModule.viewModel(type: .All, evmKit: viewModel.evmKit)
        let mineViewModel = MasterNodeModule.viewModel(type: .Mine, evmKit: viewModel.evmKit)
        allViewController = MasterNodeViewController(viewModel: allViewModel)
        mineViewController = MasterNodeViewController(viewModel: mineViewModel)
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
                    currentTabIndex: viewModel.currentTabIndex,
                    isAequilate: true
                )
                ThemeView {
                    TabView(selection: viewModel.currentTabIndex) {
                        ForEach(MasterNodeModule.Tab.allCases, id: \.self) { tab in
                            switch tab {
                            case .all:
                                MasterNodeView(viewController: allViewController)//viewModel: allViewModel)
                                    .ignoresSafeArea()
                                    .tag(tab.rawValue)
                            case .mine:
                                MasterNodeView(viewController: mineViewController)//viewModel: mineViewModel)
                                    .ignoresSafeArea()
                                    .tag(tab.rawValue)

                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .tint(.themeJacob)
            .navigationTitle("safe_zone.row.masterNode".localized)
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
                    if let viewModel = MasterNodeRegisterModule.viewModel() {
                        Coordinator.shared.present { _ in
                            MasterNodeRegisterView(viewModel: viewModel)
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
