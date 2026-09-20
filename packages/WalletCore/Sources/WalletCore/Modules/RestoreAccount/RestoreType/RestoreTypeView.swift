import SwiftUI

struct RestoreTypeView: View {
    let type: SourceType
    var onRestore: (() -> Void)? = nil
    var parentPresented: Binding<Bool>?
    var showClose: Bool = false
    @Binding var isPresented: Bool

    @StateObject private var viewModel: RestoreTypeViewModel
    @State private var path = NavigationPath()

    private enum Route: Hashable {
        case walletTypeList
        case recoveryOrPrivateKey
        case privateKey
        case backup
        case recoveryNew(walletType: MnemonicRestoreWalletType)
    }

    init(type: SourceType, onRestore: (() -> Void)? = nil, isPresented: Binding<Bool>, parentPresented: Binding<Bool>? = nil, showClose: Bool = true) {
        self.type = type
        self.onRestore = onRestore
        self.parentPresented = parentPresented
        self.showClose = showClose

        _isPresented = isPresented
        _viewModel = StateObject(wrappedValue: RestoreTypeViewModel(sourceType: type))
    }

    init(isPresented: Binding<Bool>, parentPresented: Binding<Bool>? = nil, showClose: Bool = false) {
        self.init(type: .wallet, isPresented: isPresented, parentPresented: parentPresented, showClose: showClose)
    }

    var body: some View {
        ThemeNavigationStack(path: $path) {
            ScrollableThemeView {
                VStack(spacing: .margin4) {
                    ForEach(viewModel.items) {
                        row(item: $0)
                    }

                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
            .navigationTitle(viewModel.title)
            .toolbar {
                if showClose || parentPresented != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: {
                            isPresented = false
                        }) {
                            Image("close")
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .walletTypeList:
                    WalletTypeListView(isPresented: $isPresented, path: $path, onRestore: onRestore, onSelectWallet: { walletType in
                        switch walletType {
                        case .identityWallet, .safeWallet, .imToken, .tokenPocket:
                            path.append(Route.recoveryNew(walletType: walletType))
                        }
                    })

                case .recoveryOrPrivateKey:
                    RestoreCombinedView(isPresented: $isPresented, path: $path, onRestore: handleRestore)

                case .backup:
                    RestoreBackupListView(
                        isParentPresented: parentPresented ?? $isPresented,
                        showClose: false
                    )

                case .privateKey:
                    RestorePrivateKeyView(isPresented: $isPresented, path: $path, onRestore: handleRestore)
                        .navigationTitle("restore.title".localized)

                case let .recoveryNew(walletType):
                    RestoreView(isPresented: $isPresented, path: $path, walletType: walletType, onRestore: onRestore)
                }
            }
        }
        .onReceive(viewModel.showModulePublisher) { type in
            switch type {
            case .recoveryOrPrivateKey:
                stat(page: .importWallet, event: .open(page: .importWalletFromKey))
                path.append(Route.walletTypeList)

            case .privateKey:
                path.append(Route.privateKey)

            case .backup:
                path.append(Route.backup)
            }
        }
    }

    @ViewBuilder private func row(item: RestoreTypeModule.RestoreType) -> some View {
        ListSection {
            Cell(
                left: {
                    Image(viewModel.icon(type: item)).icon(size: 24)
                },
                middle: {
                    MultiText(title: viewModel.title(type: item), subtitle: viewModel.description(type: item))
                },
                action: {
                    viewModel.onTap(type: item)
                }
            )
        }
        .padding(.top, .margin4)
    }

    private var handleRestore: () -> Void {
        if let onRestore {
            return onRestore
        }
        return { (parentPresented ?? $isPresented).wrappedValue = false }
    }

    enum SourceType {
        case wallet
        case full
    }
}
