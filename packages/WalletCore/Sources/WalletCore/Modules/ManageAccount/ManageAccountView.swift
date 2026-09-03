import SwiftUI

struct ManageAccountView: View {
    @StateObject private var viewModel: ManageAccountViewModel
    @StateObject private var accountWarningViewModel: AccountWarningViewModel

    @Binding var isPresented: Bool

    @State private var recoveryPhrasePresented = false
    @FocusState private var isNameFocused: Bool

    init(account: Account, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: ManageAccountViewModel(account: account))
        _accountWarningViewModel = StateObject(wrappedValue: AccountWarningViewModel(predefinedAccount: account, ignoreType: .auto))
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack {
            ScrollableThemeView {
                VStack(spacing: .margin24) {
                    VStack(spacing: 0) {
                        ListSectionHeader(text: "manage_account.name".localized)

                        InputTextRow {
                            InputTextView(
                                placeholder: viewModel.account.name,
                                text: $viewModel.name
                            )
                            .autocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isNameFocused)
                        }
                    }

                    AccountWarningView(viewModel: accountWarningViewModel)

                    if viewModel.account.backedUp || viewModel.isCloudBackedUp {
                        ListSection {
                            if viewModel.recoveryPhraseVisible {
                                ClickableRow(action: {
                                    Coordinator.shared.performAfterUnlock {
                                        recoveryPhrasePresented = true
                                    }
                                }) {
                                    Image("paper_contract_24").themeIcon()
                                    Text("manage_account.recovery_phrase".localized).themeBody()
                                    Image.disclosureIcon
                                }
                            }

                            if viewModel.privateKeysVisible {
                                NavigationRow(destination: {
                                    PrivateKeysView(account: viewModel.account)
                                        .navigationTitle("private_keys.title".localized)
                                        .ignoresSafeArea()
                                        .onFirstAppear {
                                            stat(page: .manageWallet, event: .open(page: .privateKeys))
                                        }
                                }) {
                                    Image("key_24").themeIcon()
                                    Text("manage_account.private_keys".localized).themeBody()
                                    Image.disclosureIcon
                                }
                            }

                            if viewModel.publicKeysVisible {
                                NavigationRow(destination: {
                                    PublicKeysView(account: viewModel.account)
                                        .navigationTitle("public_keys.title".localized)
                                        .ignoresSafeArea()
                                        .onFirstAppear {
                                            stat(page: .manageWallet, event: .open(page: .publicKeys))
                                        }
                                }) {
                                    Image("binocule_24").themeIcon()
                                    Text("manage_account.public_keys".localized).themeBody()
                                    Image.disclosureIcon
                                }
                            }
                        }
                    }

                    if viewModel.childWalletsVisible {
                        ListSection {
                            NavigationRow(destination: {
                                ChildWalletsView(account: viewModel.account)
                            }) {
                                ThemeImage("wallet", size: .iconSize24)
                                Text("子钱包").themeBody()
                                Image.disclosureIcon
                            }
                        }
                    }

                    ListSection(
                        footer: viewModel.account.backedUp || viewModel.isCloudBackedUp ? "manage_account.backup.has_backup_description".localized : "manage_account.backup.no_backup_yet_description".localized
                    ) {
                        if viewModel.account.canBeBackedUp {
                            ClickableRow {
                                Coordinator.shared.performAfterUnlock {
                                    presentBackup(reason: .manual)
                                }
                            } content: {
                                Image("edit_24").themeIcon(color: .themeJacob)
                                Text("manage_account.backup_recovery_phrase".localized).themeBody(color: .themeJacob)

                                if viewModel.account.backedUp {
                                    Image("check_1_20").themeIcon(color: .themeRemus)
                                } else {
                                    Image("warning_2_24").themeIcon(color: .themeLucian)
                                }
                            }
                        }

                    }

                    ListSection {
                        ClickableRow(action: {
                            if viewModel.account.watchAccount {
                                Coordinator.shared.present(type: .bottomSheet) { isPresented in
                                    confirmUnlinkWatchView(isPresented: isPresented)
                                }
                            } else {
                                Coordinator.shared.present(type: .bottomSheet) { isPresented in
                                    UnlinkBottomSheetView(isPresented: isPresented) {
                                        unlink()
                                    }
                                }
                            }
                        }) {
                            Image("trash_24").themeIcon(color: .themeLucian)
                            Text("manage_account.unlink".localized).themeBody(color: .themeLucian)
                        }
                    }
                }
                .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
            .onTapGesture {
                isNameFocused = false
            }
            .navigationDestination(isPresented: $recoveryPhrasePresented) {
                RecoveryPhraseView(account: viewModel.account)
                    .navigationTitle("recovery_phrase.title".localized)
                    .ignoresSafeArea()
                    .onFirstAppear {
                        stat(page: .manageWallet, event: .open(page: .recoveryPhrase))
                    }
            }
            .navigationTitle(viewModel.account.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image("close")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        viewModel.save()
                        isPresented = false
                        stat(page: .manageWallet, event: .edit(entity: .walletName))
                    }) {
                        Image("check")
                    }
                    .modifier(ConfirmationButtonStyle())
                    .disabled(viewModel.name.isEmpty || viewModel.account.name == viewModel.name)
                }
            }
        }
    }

    @ViewBuilder private func confirmUnlinkWatchView(isPresented _: Binding<Bool>) -> some View {
        BottomSheetView(
            items: [
                .title(icon: ThemeImage.trash, title: "settings_manage_keys.delete.title".localized),
                .text(text: "settings_manage_keys.delete.confirmation_watch".localized),
                .buttonGroup(.init(buttons: [
                    .init(style: .gray, title: "settings_manage_keys.delete.confirmation_watch.button".localized) {
                        unlink()
                    },
                ])),
            ],
        )
    }

    private func unlink() {
        viewModel.deleteAccount()
        HudHelper.instance.show(banner: .deleted)
        isPresented = false
    }

    private func presentBackup(reason _: BackupReason) {
        Coordinator.shared.present { _ in
            BackupManualView(account: viewModel.account)
                .ignoresSafeArea()
        }
        stat(page: .manageWallet, event: .open(page: .manualBackup))
    }
}

private enum BackupReason {
    case manual
}
