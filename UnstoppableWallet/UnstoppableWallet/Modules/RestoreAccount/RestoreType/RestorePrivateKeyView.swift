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

    var body: some View {
        ThemeView {
            BottomGradientWrapper {
                ScrollView {
                    VStack(spacing: .margin24) {
                        nameSection
                        privateKeySection
                        keyTypeSection
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
        .sheet(isPresented: $viewModel.showBip38PasswordPrompt) {
            bip38PasswordSheet
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
            LargeTextField(
                placeholder: "restore.private_key.placeholder".localized,
                text: $viewModel.text,
                statPage: .watchWallet,
                statEntity: .key,
                onButtonTap: { focusedField = nil }
            )
            .focused($focusedField, equals: .privateKey)
            .modifier(CautionBorder(cautionState: $viewModel.textCaution))
            .modifier(CautionPrompt(cautionState: $viewModel.textCaution))

            if viewModel.detectedKeyType != .unsupported {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.themeGreen)
                    Text(viewModel.detectedKeyTypeName)
                        .themeBody(color: .themeGreen)
                    Spacer()
                }
                .padding(.horizontal, .margin8)
            }
        }
    }

    private var keyTypeSection: some View {
        VStack(spacing: 0) {
            if !viewModel.availableKeyTypes.isEmpty {
                ListSectionHeader(text: "restore.private_key.format".localized)
            }
            VStack(spacing: .margin8) {
                ForEach(viewModel.availableKeyTypes, id: \.self) { type in
                    keyTypeRow(type: type)
                }
            }
            .padding(.vertical, .margin8)
        }
        .padding(.top, .margin8)
    }

    private func keyTypeRow(type: PrivateKeyType) -> some View {
        Button {
            viewModel.onSelectKeyType(type)
        } label: {
            HStack {
                Image(systemName: viewModel.selectedKeyType == type ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.selectedKeyType == type ? .themeJacob : .themeGray)
                Text(type.rawValue)
                    .themeBody(color: viewModel.selectedKeyType == type ? .themeLeah : .themeGray)
                Spacer()
            }
            .padding(.horizontal, .margin16)
        }
    }

    private var bip38PasswordSheet: some View {
        NavigationView {
            VStack(spacing: .margin24) {
                VStack(alignment: .leading, spacing: .margin8) {
                    Text("restore.private_key.bip38.enter_password".localized)
                        .themeSubhead2()

                    InputTextRow {
                        InputTextView(
                            placeholder: "restore.private_key.bip38.password_placeholder".localized,
                            text: $viewModel.bip38Password
                        )
                        .secure($bip38SecureLock)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    }

                    if let error = viewModel.bip38PasswordError {
                        Text(error)
                            .themeCaption(color: .themeRed)
                    }
                }

                VStack(spacing: .margin8) {
                    Text("restore.private_key.bip38.warning".localized)
                        .themeCaption(color: .themeGray)
                }

                Spacer()

                ThemeButton(text: "button.continue".localized, style: .primary) {
                    if viewModel.onSubmitBip38Password() {
                        viewModel.onProceed()
                    }
                }
            }
            .padding()
            .navigationTitle("restore.private_key.bip38.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("button.cancel".localized) {
                        viewModel.onCancelBip38Password()
                    }
                }
            }
        }
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
