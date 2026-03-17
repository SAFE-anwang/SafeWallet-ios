import SwiftUI

struct LiquidityRecordTabView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: LiquidityRecordTabViewModel
    @State private var loadedTabs = [LiquidityRecordModule.Tab]()
    private var safeViewController: LiquidityRecordViewController
    private var bscViewController: LiquidityRecordViewController
    private var ethViewController: LiquidityRecordViewController
    
    init(viewModel: LiquidityRecordTabViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        safeViewController = LiquidityRecordModule.subViewController(dexType: .uniswap, blockchainType: .safe4)
        bscViewController = LiquidityRecordModule.subViewController(dexType: .pancakeSwap, blockchainType: .binanceSmartChain)
        ethViewController = LiquidityRecordModule.subViewController(dexType: .uniswap, blockchainType: .ethereum)
    }

    var body: some View {
        ThemeNavigationStack {
            VStack(spacing: 0) {
                ScrollableTabHeaderView(
                    tabs: LiquidityRecordModule.Tab.allCases.map {
                        ScrollableTabHeaderView.Tab(
                            title: $0.title,
                            highlighted: false
                        )
                    },
                    currentTabIndex: Binding(
                        get: {
                            LiquidityRecordModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                        },
                        set: { index in
                            viewModel.currentTab = LiquidityRecordModule.Tab.allCases[index]
                        }
                    ),
                    isAequilate: true
                )
                ZStack {
                    
                    LiquidityRecordView(viewController: safeViewController)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .safe ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }

                    LiquidityRecordView(viewController: bscViewController)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .bsc ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }

                    LiquidityRecordView(viewController: ethViewController)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == .eth ? 1 : 0)
                        .onChange(of: viewModel.currentTab) { tab in
                            load(tab: tab)
                        }
                        .onFirstAppear {
                            load(tab: viewModel.currentTab)
                        }

                }
            }
            .tint(.themeJacob)
            .navigationTitle("liquidity.title.record".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("button.close".localized) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
            
    private func load(tab: LiquidityRecordModule.Tab) {
        guard !loadedTabs.contains(tab) else {
            return
        }

        loadedTabs.append(tab)

//        switch tab {
//        case .all: allViewModel.refresh()
//        case .mine: mineViewModel.refresh()
//        }
    }
}
