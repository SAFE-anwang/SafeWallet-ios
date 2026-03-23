import SwiftUI

enum MnemonicRestoreWalletType: String, CaseIterable, Identifiable, Hashable {
    case identityWallet
    case safeWallet
    case imToken
    case tokenPocket

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identityWallet: return "wallet_select.identity_wallet".localized
        case .safeWallet: return "wallet_select.safe_wallet".localized
        case .imToken: return "wallet_select.imtoken".localized
        case .tokenPocket: return "wallet_select.token_pocket".localized
        }
    }

    var iconName: String {
        "safe_logo_24"
    }

    var supportsPassphrase: Bool {
        self == .identityWallet
    }

    var supportsCustomPath: Bool {
        self == .identityWallet
    }

    var supportsCustomName: Bool {
        self == .identityWallet
    }

    var supportedDerivations: [MnemonicDerivation] {
        switch self {
        case .identityWallet:
            return [.bip44, .bip49, .bip84, .bip86]
        case .imToken, .tokenPocket:
            return [.bip44]
        case .safeWallet:
            return [.bip84]
        }
    }
}

struct WalletTypeListView: View {
    @Binding var isPresented: Bool
    @Binding var path: NavigationPath
    let onRestore: (() -> Void)?
    let onSelectWallet: (MnemonicRestoreWalletType) -> Void

    private let walletTypes: [MnemonicRestoreWalletType] = MnemonicRestoreWalletType.allCases

    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin12) {
                ForEach(walletTypes) { walletType in
                    ListSection {
                        Cell(
                            left: {
                                Image(walletType.iconName).renderingMode(.original)
                                    .icon(size: 24)
                            },
                            middle: {
                                Text(walletType.title)
                                    .themeBody()
                            },
                            right: {
                                Image.disclosureIcon
                            },
                            action: {
                                handleWalletSelection(walletType)
                            }
                        )
                    }
                }
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationTitle("wallet_select.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("button.cancel".localized) {
                    isPresented = false
                }
            }
        }
    }

    private func handleWalletSelection(_ walletType: MnemonicRestoreWalletType) {
        onSelectWallet(walletType)
    }
}
