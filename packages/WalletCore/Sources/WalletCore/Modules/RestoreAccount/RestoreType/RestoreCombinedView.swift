import SwiftUI

/// Entry point used by wallet types that support both mnemonic and private-key restore.
/// The actual forms remain owned by their dedicated SwiftUI views.
struct RestoreCombinedView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    let onRestore: (() -> Void)?

    @State private var showMnemonicRestore = false
    @State private var showPrivateKeyRestore = false

    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin4) {
                ListSection {
                    optionRow(
                        title: "restore_type.recovery.title".localized,
                        description: "restore_type.recovery.description".localized
                    ) {
                        showMnemonicRestore = true
                    }

                    optionRow(
                        title: "restore_type.private_key.title".localized,
                        description: "restore_type.private_key.description".localized
                    ) {
                        showPrivateKeyRestore = true
                    }
                }
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationTitle("restore.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("button.cancel".localized) {
                    isPresented = false
                }
            }
        }
        .navigationDestination(isPresented: $showMnemonicRestore) {
            RestoreView(
                isPresented: $isPresented,
                path: $path,
                walletType: .safeWallet,
                onRestore: handleRestore
            )
        }
        .navigationDestination(isPresented: $showPrivateKeyRestore) {
            RestorePrivateKeyView(
                isPresented: $isPresented,
                path: $path,
                onRestore: handleRestore
            )
        }
    }

    @ViewBuilder
    private func optionRow(title: String, description: String, action: @escaping () -> Void) -> some View {
        ClickableRow(action: action) {
            MultiText(title: title, subtitle: description)
            Spacer()
            Image.disclosureIcon
        }
    }

    private var handleRestore: () -> Void {
        onRestore ?? { isPresented = false }
    }
}
