import SwiftUI

struct RedeemSafe3TabView: View {
    @StateObject var viewModel: RedeemSafe3TabViewModel
    var localViewModel: RedeemSafe3ViewModel
    var otherViewModel: RedeemSafe3ViewModel
    @State private var loadedTabs = [RedeemSafe3Module.Tab]()
    @Binding private var isPresented: Bool

    init(viewModel: RedeemSafe3TabViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
        localViewModel = RedeemSafe3Module.viewModel(account: viewModel.account, safe4EvmKitWrapper: viewModel.safe4EvmKitWrapper, type: .local)
        otherViewModel = RedeemSafe3Module.viewModel(account: viewModel.account, safe4EvmKitWrapper: viewModel.safe4EvmKitWrapper, type: .other)
    }

    var body: some View {
        ThemeNavigationStack {
            VStack(spacing: 0) {
                ScrollableTabHeaderView(
                    tabs: RedeemSafe3Module.Tab.allCases.map {
                        ScrollableTabHeaderView.Tab(
                            title: $0.title,
                            highlighted: false
                        )
                    },
                    currentTabIndex: Binding(
                        get: {
                            RedeemSafe3Module.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                        },
                        set: { index in
                            viewModel.currentTab = RedeemSafe3Module.Tab.allCases[index]
                        }
                    ),
                    isAequilate: true
                )
                ZStack {
                    RedeemSafe3View(viewModel: otherViewModel, account: viewModel.account)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .other ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }
                    RedeemSafe3View(viewModel: localViewModel, account: viewModel.account)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .local ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }
                }
            }
            .tint(.themeJacob)
            .navigationTitle("SAFE3 -> SAFE".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image("close")
                    }
                }
            }
        }

    }

    private func load(tab: RedeemSafe3Module.Tab) {
        guard !loadedTabs.contains(tab) else {
            return
        }

        loadedTabs.append(tab)

//        switch tab {
//        case .other: otherViewModel.refresh()
//        case .local: localViewModel.refresh()
//        }
    }
}
