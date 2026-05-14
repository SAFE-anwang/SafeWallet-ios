import SwiftUI

struct ProposalTabView: View {
    @StateObject var viewModel: ProposalTabViewModel
    private var allViewModel: ProposalViewModel
    private var mineViewModel: ProposalViewModel
    @State private var loadedTabs = [ProposalModule.Tab]()
    @Binding private var isPresented: Bool

    init(viewModel: ProposalTabViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
        allViewModel = ProposalModule.viewModel(type: .All)
        mineViewModel = ProposalModule.viewModel(type: .Mine(address: viewModel.evmKit.receiveAddress.hex))
    }

    var body: some View {
        ThemeNavigationStack {
            VStack(spacing: 0) {
                ScrollableTabHeaderView(
                    tabs: ProposalModule.Tab.allCases.map {
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
            .navigationTitle("safe_zone.row.proposal".localized)
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
                guard viewModel.isEnabledAdd else {
                    HudHelper.instance.show(banner: .error(string: "safe_zone.proposal.create_height_error".localized))
                    return
                }
                let viewModel = ProposalCreateModule.viewModel(privateKey: viewModel.privateKey)
                Coordinator.shared.present { _ in
                    ProposalCreateView(viewModel: viewModel)
                        .ignoresSafeArea()
                }
            }) {
                Image("safe4_add_2_24")
                    .resizable()
                    .frame(size: 24)
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

