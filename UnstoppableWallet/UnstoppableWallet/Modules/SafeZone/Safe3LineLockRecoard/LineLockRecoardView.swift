import SwiftUI

struct LineLockRecoardView: View {
    @StateObject private var viewModel: LineLockRecoardViewModel
    @Binding private var isPresented: Bool
    
    init(viewModel: LineLockRecoardViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }
    
    var body: some View {
        ThemeNavigationStack {
            ScrollableThemeView {
                VStack(spacing: .margin8) {
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.viewItems.isEmpty {
                        emptyStateView
                    } else {
                        contentView
                    }
                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
            .navigationBarTitle("safe_zone.row.linear".localized)
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
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: .margin16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .themeLeah))
            Text("balance.syncing".localized)
                .themeSubhead2(color: .themeGray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: .margin16) {
            Image("lock_24")
                .font(.system(size: 48))
                .foregroundColor(.themeGray)
            Text("safe_lock.recoard.empty".localized)
                .themeSubhead1(color: .themeGray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: .margin8) {
            if !viewModel.lockedBalanceTitle.isEmpty {
                Text(viewModel.lockedBalanceTitle)
                    .themeSubhead1(color: .themeLeah)
                    .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            LazyVStack(spacing: .margin8) {
                ForEach(viewModel.viewItems) { item in
                    ClickableRow(action: {
                        viewModel.copyAddress(item.address)
                    }) {
                        ItemRowContent(item: item)
                    }
                }
            }
            .modifier(ThemeListStyleModifier(themeListStyle: .lawrence, selected: false))
        }
    }
    
    struct ItemRowContent: View, Equatable {
        let item: LineLockRecoardViewModel.ViewItem
        
        static func == (lhs: ItemRowContent, rhs: ItemRowContent) -> Bool {
            lhs.item == rhs.item
        }
        
        var body: some View {
            VStack(spacing: .margin8) {
                HStack(spacing: .margin8) {
                    Image(item.isLocked ? "lock_24" : "unlock_24")
                    Text("\(item.lockAmount) SAFE")
                        .themeSubhead1(color: .themeLeah)
                    Text("safe_lock.amount.locked".localized("\(item.lockMonth)"))
                        .themeSubhead1(color: .yellow, alignment: .trailing)
                }
                Text(item.address)
                    .themeSubhead1(color: .themeLeah)
            }
        }
    }
}
