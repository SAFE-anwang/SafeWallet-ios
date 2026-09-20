import Combine
import MarketKit
import SwiftUI
import UIKit

struct RestoreView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    let walletType: MnemonicRestoreWalletType
    var onRestore: (() -> Void)?

    @StateObject private var viewModel: RestoreViewModelNew

    @State private var cancellables = Set<AnyCancellable>()
    @State private var proceedEnabled = false
    @State private var bip38SecureLock = true
    @State private var showWalletSelect = false
    @State private var showBip32PathSelector = false
    @State private var showNonStandardRestore = false
    @State private var mnemonicHeightTrigger = false
    @State private var didSeedDefaultWords = false
    @State private var isEnteringMnemonic = false
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
        _viewModel = StateObject(wrappedValue: RestoreViewModelNew(walletType: walletType))
    }

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: .margin24) {
                        nameSection
                        mnemonicSection
                        advancedToggleSection
                        if viewModel.advanced {
                            advancedContent
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
                    dismissKeyboard()
                }
            } bottomContent: {
                bottomButton
            } keyboardContent: {
                if isEnteringMnemonic {
                    mnemonicHintRow
                }
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
        .navigationDestination(isPresented: $showNonStandardRestore) {
            RestoreNonStandardView(isPresented: $isPresented, path: $path, onRestore: handleRestore)
        }
        .navigationDestination(for: RestoreSelectDestination.self) { destination in
            switch destination {
            case let .selectCoins(accountName, accountType, options):
                RestoreCoinsView(
                    accountName: accountName,
                    accountType: accountType,
                    isParentPresented: $isPresented,
                    statPage: viewModel.advanced ? .importWalletFromKeyAdvanced : .importWalletFromKey,
                    allowedBitcoinDerivations: options?.allowedBitcoinDerivations ?? viewModel.allowedBitcoinDerivations,
                    allowedBlockchainTypes: options?.allowedBlockchainTypes,
                    autoEnableDefaultTokensForAllowedBlockchains: options?.autoEnableDefaultTokens ?? false,
                    blockchainsRequireManualTokenSelection: options?.blockchainsRequireManualTokenSelection,
                    onRestore: handleRestore
                )
            case let .selectAccountType(accountName, accountTypes):
                AccountTypeSelectView(
                    accountName: accountName,
                    accountTypes: accountTypes,
                    isParentPresented: $isPresented,
                    statPage: viewModel.advanced ? .importWalletFromKeyAdvanced : .importWalletFromKey,
                    onRestore: handleRestore
                )
            }
        }
        .onAppear {
            setupBindings()
            if !didSeedDefaultWords, viewModel.text.isEmpty, !AppConfig.defaultWords.isEmpty {
                didSeedDefaultWords = true
                viewModel.onChange(text: AppConfig.defaultWords, cursorOffset: AppConfig.defaultWords.utf16.count)
            }
        }
    }

    private var walletSelectSection: some View {
        ListSection {
            ClickableRow {
                showWalletSelect = true
            } content: {
                Text("restore.wallet.name".localized).themeBody()
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
            MnemonicInputCellWrapper(
                statPage: .importWalletFromKey,
                placeholder: "restore.mnemonic.placeholder".localized,
                text: $viewModel.text,
                invalidRanges: $viewModel.invalidRanges,
                cautionType: viewModel.textCaution.caution?.type,
                replaceWordPublisher: viewModel.replaceWordPublisher,
                heightTrigger: $mnemonicHeightTrigger,
                isFocused: Binding(
                    get: { focusedField == .mnemonic },
                    set: { focusedField = $0 ? .mnemonic : nil }
                ),
                onChangeMnemonicText: { text, cursorOffset in
                    viewModel.onChange(text: text, cursorOffset: cursorOffset)
                },
                onChangeEntering: handleMnemonicEntering
            )
            .modifier(CautionBorder(cautionState: $viewModel.textCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.textCaution))

        }
    }

    private var advancedToggleSection: some View {
        ListSection {
            ListRow {
                Text("create_wallet.advanced_options".localized)
                Spacer()
                ThemeToggle(
                    isOn: Binding(
                        get: { viewModel.advanced },
                        set: viewModel.onToggleAdvanced
                    )
                )
            }
        }
    }

    private var advancedContent: some View {
        VStack(spacing: .margin24) {
            wordListSection
            if viewModel.supportsPassphrase {
                passwordToggleSection
                if viewModel.requirePassword {
                    passwordInputSection
                }
            }
            nonStandardRestoreSection
        }
    }

    private var wordListSection: some View {
        ListSection {
            ClickableRow {
                Coordinator.shared.present(type: .alert) { isPresented in
                    OptionAlertView(
                        title: "create_wallet.word_list".localized,
                        viewItems: viewModel.wordListViewItems,
                        onSelect: viewModel.onSelectWordList,
                        isPresented: isPresented
                    )
                }
            } content: {
                Text("create_wallet.word_list".localized).themeBody()
                Spacer()
                Text(viewModel.wordListLanguage).themeSubhead2(alignment: .trailing)
                Image.disclosureIcon
            }
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

    private var nonStandardRestoreSection: some View {
        ListSection {
            ClickableRow {
                showNonStandardRestore = true
                stat(page: .importWalletFromKeyAdvanced, event: .open(page: .importWalletNonStandard))
            } content: {
                Text("restore.non_standard_import".localized).themeBody()
                Spacer()
                Image.disclosureIcon
            }
        }
    }

    @ViewBuilder private var mnemonicHintRow: some View {
        if viewModel.possibleWords.isEmpty {
            ThemeText("restore.suggestions".localized, style: .caption)
                .frame(height: ThemeButton.Size.small.size)
                .padding(.bottom, .margin8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .margin8) {
                    ForEach(viewModel.possibleWords, id: \.self) { word in
                        ThemeButton(text: word, style: .secondary, size: .small) {
                            viewModel.onSelect(word: word)
                        }
                    }
                }
                .padding(.horizontal, .margin16)
                .padding(.bottom, .margin8)
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
            .disabled(!proceedEnabled)
        }
    }

    private func handleNextButtonTap() {

        if viewModel.supportsCustomName {
            viewModel.walletNameCaution = .none
            viewModel.bip32PathCaution = .none

            let hasWalletName = !viewModel.selectedWalletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBip32Path = !viewModel.selectedWalletBip32Paths.isEmpty

            if !hasWalletName {
                viewModel.walletNameCaution = .caution(Caution(text: "restore.please_select_wallet_name".localized, type: .error))
                showError(message: "restore.please_select_wallet_name".localized)
                return
            }

            if !hasBip32Path {
                viewModel.bip32PathCaution = .caution(Caution(text: "restore.please_select_bip32_path".localized, type: .error))
                showError(message: "restore.please_select_bip32_path".localized)
                return
            }
        }

        viewModel.onProceed()
    }

    private func handleMnemonicEntering(_ isEntering: Bool) {
        isEnteringMnemonic = isEntering
        if isEntering {
            focusedField = .mnemonic
        } else if focusedField == .mnemonic {
            focusedField = nil
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        isEnteringMnemonic = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        let tokens = RestoreCoinsViewModel.supportedTokens(accountType: accountType)
        let blockchains = Set(tokens.map(\.blockchainType))
        if blockchains.count == 1,
           let token = tokens.first,
           token.blockchainType.restoreSettingTypes.isEmpty,
           isAllowedForSingleBlockchainRestore(token: token) {
            RestoreCoinsViewModel.restoreSingleBlockchain(
                accountName: accountName,
                accountType: accountType,
                token: token,
                statPage: viewModel.advanced ? .importWalletFromKeyAdvanced : .importWalletFromKey
            )
            handleRestore()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            path.append(RestoreSelectDestination.selectCoins(accountName: accountName, accountType: accountType, options: nil))
        }
    }

    private func isAllowedForSingleBlockchainRestore(token: Token) -> Bool {
        guard let allowedDerivations = viewModel.allowedBitcoinDerivations else {
            return true
        }

        guard token.blockchainType == .bitcoin || token.blockchainType == .litecoin else {
            return true
        }

        guard let derivation = token.type.derivation else {
            return true
        }

        return allowedDerivations.contains(derivation)
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
