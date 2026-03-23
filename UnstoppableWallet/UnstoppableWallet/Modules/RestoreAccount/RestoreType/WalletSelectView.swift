import SwiftUI

struct WalletSelectView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    let onRestore: (() -> Void)?
    let onSelectWallet: (WalletItem) -> Void
    
    @StateObject private var viewModel = WalletSelectViewModel()
    @State private var showSearch: Bool = false
    @FocusState var isInputActive: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if showSearch {
                headerView
            }
            
            ScrollableTabHeaderView(
                tabs: viewModel.tabTitles,
                currentTabIndex: $viewModel.currentTabIndex
            )
            
            TabView(selection: $viewModel.currentTabIndex) {
                ForEach(viewModel.categories.indices, id: \.self) { index in
                    walletListView(category: viewModel.categories[index])
                        .tag(index)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("wallet_select.title".localized)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                searchButton
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button.done".localized) {
                    isInputActive = false
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("wallet_select.search".localized, text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($isInputActive)
                
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            Spacer()
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .background(Color.themeTyler)
    }
    
    private var searchButton: some View {
        Button {
            withAnimation {
                showSearch.toggle()
                if !showSearch {
                    viewModel.searchText = ""
                    isInputActive = false
                }else {
                    isInputActive = true
                }
            }
        } label: {
            Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                .foregroundColor(.themeJacob)
        }
    }
    
    @ViewBuilder
    private func walletListView(category: String) -> some View {
        let wallets = viewModel.wallets(for: category)
        
        if wallets.isEmpty {
            PlaceholderViewNew(icon: "warning_filled", subtitle: "alert.not_founded".localized)
        } else {
            ScrollableThemeView {
                VStack(spacing: .margin12) {
                    ListSection {
                        ListForEach(wallets) { wallet in
                            walletCell(wallet: wallet)
                        }
                    }
                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
        }
    }
    
    @ViewBuilder
    private func walletCell(wallet: WalletItem) -> some View {
        ClickableRow {
            handleWalletSelection(wallet)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(wallet.name)
                    .themeBody()
                Text(viewModel.categoryName(for: wallet.wallet))
                    .themeSubhead2()
                    .foregroundColor(.themeNina)
                
            }
        }

//        ClickableRow {
//            VStack(alignment: .leading, spacing: 4) {
//                Text(wallet.name)
//                    .themeBody()
//                Text(viewModel.categoryName(for: wallet.wallet))
//                    .themeSubhead2()
//                    .foregroundColor(.themeNina)
//                
//            }
//            .onTapGesture {
//                
//            }
//        }
    }
    
    private func handleWalletSelection(_ wallet: WalletItem) {
        isPresented = false
        onSelectWallet(wallet)
    }
}
