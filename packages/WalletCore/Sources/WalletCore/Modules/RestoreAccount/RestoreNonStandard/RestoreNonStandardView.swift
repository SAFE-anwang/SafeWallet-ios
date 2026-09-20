import SwiftUI
import UIKit

struct RestoreNonStandardView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    var onRestore: (() -> Void)?

    @StateObject private var viewModel = RestoreNonStandardViewModel()
    @State private var mnemonicHeightTrigger = false
    @State private var isMnemonicFocused = false
    @State private var isEnteringMnemonic = false
    @State private var passwordSecure = true
    @State private var didSeedDefaultWords = false

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: .margin24) {
                        Text("restore.non_standard_import.description".localized(AppConfig.appName, AppConfig.appName))
                            .themeSubhead2(color: .themeGray)
                        nameSection
                        mnemonicSection
                        wordListSection
                        passphraseSection
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                }
                .onTapGesture {
                    dismissKeyboard()
                }
            } bottomContent: {
                ThemeButton(text: "button.next".localized, style: .primary) {
                    viewModel.onProceed()
                }
                .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } keyboardContent: {
                if isEnteringMnemonic {
                    mnemonicHintRow
                }
            }
        }
        .navigationTitle("restore.non_standard_import".localized)
        .onAppear {
            guard !didSeedDefaultWords, viewModel.text.isEmpty, !AppConfig.defaultWords.isEmpty else { return }
            didSeedDefaultWords = true
            viewModel.onChange(text: AppConfig.defaultWords, cursorOffset: AppConfig.defaultWords.utf16.count)
        }
        .onReceive(viewModel.proceedSubject) { accountName, accountType in
            path.append(RestoreSelectDestination.selectCoins(accountName: accountName, accountType: accountType, options: nil))
        }
        .onReceive(viewModel.errorSubject) { HudHelper.instance.show(banner: .error(string: $0)) }
        .navigationDestination(for: RestoreSelectDestination.self) { destination in
            switch destination {
            case let .selectCoins(accountName, accountType, options):
                RestoreCoinsView(
                    accountName: accountName,
                    accountType: accountType,
                    isParentPresented: $isPresented,
                    statPage: .importWalletNonStandard,
                    allowedBitcoinDerivations: options?.allowedBitcoinDerivations,
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
                    statPage: .importWalletNonStandard,
                    onRestore: handleRestore
                )
            }
        }
    }

    private var nameSection: some View {
        VStack(spacing: 0) {
            ListSectionHeader(text: "create_wallet.name".localized, uppercased: false)
            InputTextRow {
                InputTextView(text: $viewModel.name)
                    .autocapitalization(.words)
                    .autocorrectionDisabled()
            }
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
                isFocused: $isMnemonicFocused,
                onChangeMnemonicText: viewModel.onChange,
                onChangeEntering: handleMnemonicEntering
            )
            .modifier(CautionBorder(cautionState: $viewModel.textCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.textCaution))
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
                        ThemeButton(text: word, style: .secondary, size: .small) { viewModel.onSelect(word: word) }
                    }
                }
                .padding(.horizontal, .margin16)
                .padding(.bottom, .margin8)
            }
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

    private var passphraseSection: some View {
        VStack(spacing: .margin12) {
            ListSection {
                ListRow {
                    Image("key_phrase_24")
                    Text("restore.passphrase".localized)
                    Spacer()
                    ThemeToggle(isOn: Binding(get: { viewModel.requirePassword }, set: viewModel.onTogglePassphrase), style: .yellow)
                }
            }
            if viewModel.requirePassword {
                InputTextRow {
                    InputTextView(
                        placeholder: "restore.input.passphrase".localized,
                        text: Binding(
                            get: { viewModel.password },
                            set: viewModel.onChangePassword
                        )
                    )
                        .secure($passwordSecure)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                .modifier(CautionBorder(cautionState: $viewModel.passwordCaution))
                .modifier(CautionPrompt(cautionState: $viewModel.passwordCaution))
                HighlightedTextView(text: "restore.wallet.passphrase_description".localized)
            }
        }
    }

    private var handleRestore: () -> Void {
        onRestore ?? { isPresented = false }
    }

    private func handleMnemonicEntering(_ isEntering: Bool) {
        isEnteringMnemonic = isEntering
        isMnemonicFocused = isEntering
    }

    private func dismissKeyboard() {
        isMnemonicFocused = false
        isEnteringMnemonic = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
