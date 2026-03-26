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
    @State private var showBip32PathSelector = false
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
                        passwordToggleSection
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
        .modifier(CautionBorder(cautionState: $viewModel.walletNameCaution))
        .modifier(CautionPrompt(cautionState: $viewModel.walletNameCaution))
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
        .disabled(!viewModel.supportsPassphrase)
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
                    showBip32PathSelector = true
                } content: {
                    HStack {
                        Text(viewModel.selectedWalletBip32Paths[viewModel.currentBip32PathIndex])
                            .themeBody()
                        Spacer()
                        Image("arrow_big_up_20").themeIcon()
                    }
                }
            }
            .modifier(CautionBorder(cautionState: $viewModel.bip32PathCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.bip32PathCaution))
        }
        .sheet(isPresented: $showBip32PathSelector) {
            bip32PathSelectorSheet
        }
    }
    
    private var bip32PathSelectorSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    ListSection {
                        ForEach(viewModel.selectedWalletBip32Paths.indices, id: \.self) { index in
                            ClickableRow {
                                viewModel.currentBip32PathIndex = index
                                showBip32PathSelector = false
                            } content: {
                                HStack {
                                    Text(viewModel.selectedWalletBip32Paths[index])
                                        .themeBody()
                                    Spacer()
                                    if index == viewModel.currentBip32PathIndex {
                                        Image("check_1_20")
                                            .themeIcon(color: .themeJacob)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, .margin12)
            }
            .background(Color.themeLawrence)
            .navigationTitle("restore.bip32_path".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("button.done".localized) {
                        showBip32PathSelector = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
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
                handleNextButtonTap()
            }
        }
    }

    private func handleNextButtonTap() {
        if viewModel.supportsCustomName {
            viewModel.walletNameCaution = .none
            viewModel.bip32PathCaution = .none

            let hasWalletName = !viewModel.selectedWalletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBip32Path = !viewModel.selectedWalletBip32Paths.isEmpty

            if !hasWalletName {
                viewModel.walletNameCaution = .caution(Caution(text: "请先选择钱包名称", type: .error))
                showError(message: "请先选择钱包名称")
                return
            }

            if !hasBip32Path {
                viewModel.bip32PathCaution = .caution(Caution(text: "请先选择BIP32路径", type: .error))
                showError(message: "请先选择BIP32路径")
                return
            }
        }

        viewModel.onProceed()
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
