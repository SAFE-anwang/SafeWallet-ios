import Combine
import SwiftUI
import UIKit

struct RestorePrivateKeyView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    var onRestore: (() -> Void)?

    @StateObject private var viewModel = RestorePrivateKeyViewModelNew(
        service: RestoreService(accountFactory: Core.shared.accountFactory),
        privateKeyService: RestorePrivateKeyService()
    )

    @State private var cancellables = Set<AnyCancellable>()
    @State private var proceedEnabled = false
    @State private var bip38SecureLock = true
    @FocusState private var focusedField: RestorePrivateKeyView.Field?
    @State private var passwordFieldShake = false
    @State private var showPasteConfirmation = false
    @State private var pendingPasteText: String = ""

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: .margin24) {
                        nameSection
                        privateKeySection
                        passwordSection
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
        .navigationTitle("restore.title".localized)
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
        .sheet(isPresented: $viewModel.showSecurityConfirmation) {
            securityConfirmationSheet
        }
        .alert("restore.private_key.paste_confirm_title".localized, isPresented: $showPasteConfirmation) {
            Button("button.cancel".localized, role: .cancel) {
                pendingPasteText = ""
            }
            Button("button.confirm".localized) {
                viewModel.onPaste(text: pendingPasteText)
                pendingPasteText = ""
            }
        } message: {
            Text("restore.private_key.paste_confirm_message".localized)
        }
        .navigationDestination(for: RestoreSelectDestination.self) { destination in
            switch destination {
            case let .selectCoins(accountName, accountType):
                RestoreSelectWrapperNew(
                    accountName: accountName,
                    accountType: accountType,
                    statPage: .importWalletFromKey,
                    allowedBitcoinDerivations: nil,
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

    private var privateKeySection: some View {
        VStack(spacing: .margin8) {
            ZStack {
                LargeTextField(
                    placeholder: "restore.private_key.placeholder".localized,
                    text: $viewModel.text,
                    statPage: .watchWallet,
                    statEntity: .key,
                    onButtonTap: { focusedField = nil },
                    onPaste: { pastedText in
                        pendingPasteText = pastedText
                        showPasteConfirmation = true
                    },
                    onScan: { scannedText in
                        viewModel.onScan(text: scannedText)
                    }
                )
                .focused($focusedField, equals: .privateKey)
                .modifier(CautionBorder(cautionState: $viewModel.textCaution))
                .modifier(CautionPrompt(cautionState: $viewModel.textCaution))
                
                if viewModel.isValidatingInput {
                    Color.themeLawrence.opacity(0.8)
                        .cornerRadius(.cornerRadius12)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .themeJacob))
                        )
                }
            }

            // Key type detection indicator
            if viewModel.detectedKeyType != .unsupported {
                HStack(spacing: .margin8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.themeGreen)
                        .frame(width: 20, height: 20)
                    Text(viewModel.detectedKeyTypeName)
                        .themeBody(color: .themeGreen)
                    Spacer()
                }
                .padding(.horizontal, .margin8)
            }

            // Password required indicator - shown immediately when BIP38 is detected
            if viewModel.requiresPassword {
                HStack(spacing: .margin8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.themeJacob)
                        .frame(width: 20, height: 20)
                    Text("restore.private_key.password_required_hint".localized)
                        .themeCaption(color: .themeJacob)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, .margin8)
                .padding(.top, .margin4)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.requiresPassword)
            }
        }
    }

    private var passwordSection: some View {
        Group {
            if viewModel.requiresPassword {
                VStack(spacing: .margin12) {
                    ListSectionHeader(text: "restore.private_key.password_section_title".localized)

                    VStack(spacing: .margin8) {
                        InputTextRow {
                            InputTextView(
                                placeholder: "restore.private_key.password_placeholder".localized,
                                text: $viewModel.password
                            )
                            .secure($bip38SecureLock)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                        }
                        .modifier(CautionBorder(cautionState: $viewModel.passwordCaution))

                        if let hint = viewModel.passwordHint {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.themeGray)
                                    .frame(width: 20, height: 20)
                                Text(hint)
                                    .themeCaption(color: .themeGray)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(.horizontal, .margin8)
                        }

                        if case .caution(let caution) = viewModel.passwordCaution {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.themeRed)
                                    .frame(width: 20, height: 20)
                                Text(caution.text)
                                    .themeCaption(color: .themeRed)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(.horizontal, .margin8)
                        }

                        if let errorWarning = viewModel.passwordErrorWarning {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundColor(.themeJacob)
                                    .frame(width: 20, height: 20)
                                Text(errorWarning)
                                    .themeCaption(color: .themeJacob)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                            .padding(.horizontal, .margin8)
                            .padding(.vertical, .margin8)
                            .background(Color.themeJacob.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.themeGray)
                            .frame(width: 20, height: 20)
                        Text("restore.private_key.password_security_hint".localized)
                            .themeCaption(color: .themeGray)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, .margin8)
                    .padding(.top, .margin4)
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity.combined(with: .move(edge: .top))))
                .animation(.easeInOut(duration: 0.25), value: viewModel.requiresPassword)
            }
        }
    }

    private var securityConfirmationSheet: some View {
        NavigationView {
            VStack(spacing: .margin24) {
                VStack(spacing: .margin16) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.themeJacob)
                    
                    Text("restore.private_key.scan_confirm_title".localized)
                        .themeHeadline1()
                        .multilineTextAlignment(.center)
                    
                    Text("restore.private_key.scan_confirm_message".localized)
                        .themeBody()
                        .multilineTextAlignment(.center)
                        .foregroundColor(.themeGray)
                }
                .padding(.horizontal, .margin24)
                .padding(.top, .margin32)
                
                // Show detected key type
                if viewModel.detectedKeyType != .unsupported {
                    VStack(spacing: .margin8) {
                        Text("restore.private_key.detected_format".localized)
                            .themeSubhead2()
                        
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.themeGreen)
                            Text(viewModel.detectedKeyTypeName)
                                .themeBody(color: .themeGreen)
                            Spacer()
                        }
                        .padding()
                        .background(Color.themeLawrence)
                        .cornerRadius(.cornerRadius12)
                    }
                    .padding(.horizontal, .margin24)
                }
                
                // Show partial key for confirmation (masked)
                if !viewModel.text.isEmpty {
                    VStack(alignment: .leading, spacing: .margin8) {
                        Text("restore.private_key.scanned_content".localized)
                            .themeSubhead2()
                        
                        Text(maskedKey(viewModel.text))
                            .themeBody()
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color.themeLawrence)
                            .cornerRadius(.cornerRadius12)
                    }
                    .padding(.horizontal, .margin24)
                }
                
                Spacer()
                
                VStack(spacing: .margin16) {
                    ThemeButton(text: "button.confirm".localized, style: .primary) {
                        viewModel.confirmScannedInput()
                    }
                    
                    ThemeButton(text: "button.cancel".localized, style: .secondary) {
                        viewModel.rejectScannedInput()
                    }
                }
                .padding(.horizontal, .margin24)
                .padding(.bottom, .margin32)
            }
            .navigationTitle("restore.private_key.security_check".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return key }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
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

    private var handleRestore: () -> Void {
        if let onRestore {
            return onRestore
        }
        return { isPresented = false }
    }

    private func showError(message: String) {
        HudHelper.instance.show(banner: .error(string: message))
    }
}

enum RestoreSelectDestination: Hashable {
    case selectCoins(accountName: String, accountType: AccountType)
}

struct RestoreSelectWrapperNew: UIViewControllerRepresentable {
    let accountName: String
    let accountType: AccountType
    let statPage: StatPage
    let allowedBitcoinDerivations: Set<MnemonicDerivation>?
    let onRestore: () -> Void

    func makeUIViewController(context _: Context) -> UINavigationController {
        let vc = RestoreSelectModule.viewController(
            accountName: accountName,
            accountType: accountType,
            statPage: statPage,
            isManualBackedUp: true,
            allowedBitcoinDerivations: allowedBitcoinDerivations,
            onRestore: onRestore
        )

        let navController = UINavigationController(rootViewController: vc)
        navController.navigationBar.prefersLargeTitles = false
        navController.setNavigationBarHidden(false, animated: false)

        return navController
    }

    func updateUIViewController(_: UINavigationController, context _: Context) {}
}

extension RestorePrivateKeyView {
    enum Field: Int, Hashable {
        case name
        case privateKey
    }
}
