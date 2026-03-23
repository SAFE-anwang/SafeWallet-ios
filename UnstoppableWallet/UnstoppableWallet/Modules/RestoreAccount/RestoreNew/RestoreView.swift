import Combine
import SwiftUI
import UIKit

struct RestoreView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    let walletType: MnemonicRestoreWalletType
    var onRestore: (() -> Void)?

    @StateObject private var viewModel: RestoreViewModel

    @State private var cancellables = Set<AnyCancellable>()
    @State private var proceedEnabled = false
    @State private var bip38SecureLock = true
    @State private var showWalletSelect = false
    @FocusState private var focusedField: Field?

    init(
        isPresented: Binding<Bool>,
        path: Binding<NavigationPath>,
        walletType: MnemonicRestoreWalletType,
        onRestore: (() -> Void)? = nil
    ) {
        _isPresented = isPresented
        _path = path
        self.walletType = walletType
        self.onRestore = onRestore
        _viewModel = StateObject(wrappedValue: RestoreViewModel(walletType: walletType))
    }

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: .margin24) {
                        nameSection
                        mnemonicSection
                        if viewModel.supportsPassphrase {
                            passwordToggleSection
                        }
                        if viewModel.requirePassword {
                            passwordInputSection
                        }
                        if viewModel.supportsCustomName {
                            walletSelectSection
                        }
                        if viewModel.supportsCustomName, !viewModel.selectedWalletBip32Paths.isEmpty {
                            bip32PathSection
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                }
                .onTapGesture {
                    focusedField = nil
                }
            } bottomContent: {
                bottomButton
            }
        }
        .navigationTitle(walletType.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("button.cancel".localized) {
                    isPresented = false
                }
            }
        }
        .onReceive(viewModel.proceedSubject) { accountName, accountType in
            navigateToSelectCoins(accountName: accountName, accountType: accountType)
        }
        .onReceive(viewModel.errorSubject) { errorMessage in
            showError(message: errorMessage)
        }
        .navigationDestination(isPresented: $showWalletSelect) {
            WalletSelectView(
                isPresented: $showWalletSelect,
                path: $path,
                onRestore: nil,
                onSelectWallet: { wallet in
                    viewModel.selectedWalletName = wallet.name
                    viewModel.selectedWalletBip32Paths = wallet.bip32path
                    viewModel.currentBip32PathIndex = 0
                }
            )
        }
        .navigationDestination(for: RestoreSelectDestination.self) { destination in
            switch destination {
            case let .selectCoins(accountName, accountType):
                RestoreSelectWrapperNew(
                    accountName: accountName,
                    accountType: accountType,
                    statPage: .importWalletFromKey,
                    allowedBitcoinDerivations: viewModel.allowedBitcoinDerivations,
                    onRestore: handleRestore
                )
                .ignoresSafeArea()
                .navigationBarHidden(true)
            }
        }
        .onAppear {
            setupBindings()
        }
    }

    private var walletSelectSection: some View {
        ListSection {
            ClickableRow {
                showWalletSelect = true
            } content: {
                Text("钱包名称").themeBody()
                Spacer()
                Text(viewModel.selectedWalletName).themeSubhead2(alignment: .trailing)
                Image("arrow_big_forward_20")
            }
        }
    }

    private var nameSection: some View {
        VStack(spacing: 0) {
            ListSectionHeader(text: "watch_address.name".localized)
            InputTextRow {
                InputTextView(
                    placeholder: viewModel.defaultAccountName,
                    text: $viewModel.name
                )
                .autocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .name)
            }
            .modifier(CautionBorder(cautionState: $viewModel.nameCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.nameCaution))
        }
    }

    private var mnemonicSection: some View {
        VStack(spacing: .margin8) {
            LargeTextField(
                placeholder: "restore.mnemonic.placeholder".localized,
                text: $viewModel.text,
                statPage: .watchWallet,
                statEntity: .key,
                onButtonTap: { focusedField = nil }
            )
            .focused($focusedField, equals: .mnemonic)
            .modifier(CautionBorder(cautionState: $viewModel.textCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.textCaution))
        }
    }
    
    private var passwordToggleSection: some View {
        ListSection {
            ListRow {
                Image("key_phrase_24")
                Text("restore.passphrase".localized)
                Spacer()
                ThemeToggle(isOn: $viewModel.requirePassword, style: .yellow)
            }
        }
    }
    
    private var passwordInputSection: some View {
        VStack {
            InputTextRow {
                InputTextView(
                    placeholder: "restore.input.passphrase".localized,
                    text: $viewModel.password
                )
                .secure($bip38SecureLock)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .passphrase)
            }
            .modifier(CautionBorder(cautionState: $viewModel.passwordCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.passwordCaution))
            
            HighlightedTextView(text: "restore.wallet.passphrase_description".localized)
        }
    }

    private var bip32PathSection: some View {
        VStack(spacing: 0) {
            ListSectionHeader(text: "restore.bip32_path".localized)
            ListSection {
                ClickableRow {
                    // to do ... show 
                } content: {
                    HStack {
                        Text(viewModel.selectedWalletBip32Paths[viewModel.currentBip32PathIndex])
                            .themeBody()
                        Spacer()
                        if viewModel.supportsCustomPath {
                            HStack(spacing: .margin16) {
                                Button(action: {
                                    if viewModel.currentBip32PathIndex > 0 {
                                        viewModel.currentBip32PathIndex -= 1
                                    }
                                }) {
                                    Image("arrow_up_20").themeIcon()
                                }
                                .disabled(viewModel.currentBip32PathIndex == 0)

                                Button(action: {
                                    if viewModel.currentBip32PathIndex < viewModel.selectedWalletBip32Paths.count - 1 {
                                        viewModel.currentBip32PathIndex += 1
                                    }
                                }) {
                                    Image("arrow_down_20").themeIcon()
                                }
                                .disabled(viewModel.currentBip32PathIndex == viewModel.selectedWalletBip32Paths.count - 1)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var handleRestore: () -> Void {
        if let onRestore {
            return onRestore
        }
        return { isPresented = false }
    }
    
    @ViewBuilder
    private var bottomButton: some View {
        if viewModel.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .themeJacob))
        } else {
            ThemeButton(text: "button.next".localized, style: .primary) {
                viewModel.onProceed()
            }
            .disabled(!proceedEnabled)
            .opacity(proceedEnabled ? 1 : 0.5)
        }
    }

    private func setupBindings() {
        cancellables.removeAll()

        viewModel.proceedEnabled
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                proceedEnabled = enabled
            }
            .store(in: &cancellables)
    }

    private func navigateToSelectCoins(accountName: String, accountType: AccountType) {
        withAnimation(.easeInOut(duration: 0.3)) {
            path.append(RestoreSelectDestination.selectCoins(accountName: accountName, accountType: accountType))
        }
    }

    private func showError(message: String) {
        HudHelper.instance.show(banner: .error(string: message))
    }
}

extension RestoreView {
    enum Field: Int, Hashable {
        case name
        case mnemonic
        case passphrase
    }
}
