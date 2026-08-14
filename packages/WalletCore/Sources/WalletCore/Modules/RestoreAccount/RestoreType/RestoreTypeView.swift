import SwiftUI
import UIKit

struct RestoreTypeView: View {
    let type: SourceType
    var onRestore: (() -> Void)? = nil
    var parentPresented: Binding<Bool>?
    var showClose: Bool = false
    @Binding var isPresented: Bool

    @StateObject private var viewModel: RestoreTypeViewModel
    @State private var path = NavigationPath()
    @State private var showFilePicker = false
    @State private var namedSource: BackupModule.NamedSource?
    @State private var selectCoinsAccount: Account?
    @State private var fileConfigRawBackup: RawFullBackup?
    @State private var backupPresented = false
    @State private var passkeyLogin: RestoreTypeViewModel.PasskeyLogin?
    @State private var restoreSelectPresented = false

    private enum Route: Hashable {
        case walletTypeList
        case recoveryOrPrivateKey
        case passphrase
        case selectCoins
        case privateKey
        case recoveryNew(walletType: MnemonicRestoreWalletType)
    }

    init(type: SourceType, onRestore: (() -> Void)? = nil, isPresented: Binding<Bool>, parentPresented: Binding<Bool>? = nil, showClose: Bool = true) {
        self.type = type
        self.onRestore = onRestore
        self.parentPresented = parentPresented
        self.showClose = showClose

        _isPresented = isPresented
        _viewModel = StateObject(wrappedValue:
            RestoreTypeViewModel(
                cloudAccountBackupManager: Core.shared.cloudBackupManager,
                sourceType: type
            )
        )
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

                    if case .full = type {
                        legacyRow(
                            icon: "cloud",
                            title: "restore_type.backup.title".localized,
                            description: "restore_type.backup.description".localized,
                            action: { backupPresented = true }
                        )
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
                        case .identityWallet, .imToken, .tokenPocket:
                            path.append(Route.recoveryNew(walletType: walletType))
                        case .safeWallet:
                            path.append(Route.recoveryOrPrivateKey)
                        }
                    })

                case .recoveryOrPrivateKey:
                    RestoreViewWrapper(advanced: false, initialRestoreType: .mnemonic, onRestore: handleRestore)
                        .ignoresSafeArea()
                        .navigationTitle("restore.title".localized)

                case .privateKey:
                    RestorePrivateKeyView(isPresented: $isPresented, path: $path, onRestore: handleRestore)
                        .navigationTitle("restore.title".localized)

                case .passphrase:
                    if let source = namedSource {
                        showPassphrase(source)
                    }
                case .selectCoins:
                    if let account = selectCoinsAccount {
                        RestoreSelectWrapper(account: account, statPage: passphraseStatPage, onRestore: handleRestore)
                            .ignoresSafeArea()
                            .navigationTitle("restore.title".localized)
                    }

                case let .recoveryNew(walletType):
                    RestoreView(isPresented: $isPresented, path: $path, walletType: walletType, onRestore: onRestore)
                }
            }
            .navigationDestination(isPresented: $backupPresented) {
                RestoreBackupListView(isParentPresented: parentPresented ?? $isPresented)
            }
            .navigationDestination(isPresented: $restoreSelectPresented) {
                if let passkeyLogin {
                    RestoreCoinsView(
                        accountName: passkeyLogin.accountName,
                        accountType: passkeyLogin.accountType,
                        isParentPresented: parentPresented ?? $isPresented
                    )
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                viewModel.didPick(url: url, destination: .files)
            }
        }
        .onReceive(viewModel.showModulePublisher) { type in
            switch type {
            case .recoveryOrPrivateKey:
                stat(page: .importWallet, event: .open(page: .importWalletFromKey))
                path.append(Route.walletTypeList)

            case .privateKey:
                path.append(Route.privateKey)
            }
        }
        .onReceive(viewModel.showCloudNotAvailablePublisher) {
            showCloudNotAvailable()
        }
        .onReceive(viewModel.showWrongFilePublisher) {
            HudHelper.instance.show(banner: .error(string: "alert.cant_recognize".localized))
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

    @ViewBuilder private func legacyRow(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        ListSection {
            Cell(
                left: {
                    ThemeImage(icon, size: 24)
                },
                middle: {
                    MultiText(title: title, subtitle: description)
                },
                right: {
                    Image.disclosureIcon
                },
                action: action
            )
        }
        .padding(.top, .margin4)
    }

    private func restorePasskey() {
        Task {
            do {
                let login = try await viewModel.loginPasskey()

                await MainActor.run {
                    passkeyLogin = login
                    restoreSelectPresented = true
                }
            } catch {
                if case PasskeyManager.PasskeyError.userCanceled = error {
                    return
                }
                await MainActor.run {
                    HudHelper.instance.show(banner: .error(string: error.smartDescription))
                }
            }
        }
    }

    @ViewBuilder private func showPassphrase(_ source: BackupModule.NamedSource) -> some View {
        RestorePassphraseView(
            item: source,
            isParentPresented: parentPresented ?? $isPresented
        )
    }

    private func showCloudNotAvailable() {
        Coordinator.shared.present(type: .bottomSheet) { isPresented in
            BottomSheetView(
                items: [
                    .title(icon: ComponentImage("icloud_24", size: .iconSize72, colorStyle: .yellow), title: "backup.cloud.no_access.title".localized),
                    .warning(text: "backup.cloud.no_access.description".localized),
                    .buttonGroup(.init(buttons: [
                        .init(style: .yellow, title: "button.ok".localized) {
                            isPresented.wrappedValue = false
                        },
                    ])),
                ]
            )
        }
    }

    private var handleRestore: () -> Void {
        if let onRestore {
            return onRestore
        }
        return { (parentPresented ?? $isPresented).wrappedValue = false }
    }

    private var passphraseStatPage: StatPage {
        viewModel.sourceType == .wallet ? .importWalletFromFiles : .importFullFromFiles
    }

    enum SourceType {
        case wallet
        case full
    }
}

private struct RestoreViewWrapper: UIViewControllerRepresentable {
    let advanced: Bool
    let initialRestoreType: RestoreViewModel.RestoreType
    let onRestore: () -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        RestoreModule.viewController(advanced: advanced, initialRestoreType: initialRestoreType, onRestore: onRestore)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

private struct RestoreSelectWrapper: UIViewControllerRepresentable {
    let account: Account
    let statPage: StatPage
    let onRestore: () -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        RestoreSelectModule.viewController(
            accountName: account.name,
            accountType: account.type,
            statPage: statPage,
            isManualBackedUp: account.backedUp,
            isFileBackedUp: account.fileBackedUp,
            onRestore: onRestore
        )
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
