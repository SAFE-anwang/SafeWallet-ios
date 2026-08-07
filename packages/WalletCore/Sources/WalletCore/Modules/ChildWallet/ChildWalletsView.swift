import SwiftUI

struct ChildWalletsView: View {
    @StateObject private var viewModel: ChildWalletsViewModel
    @State private var showError = false
    @State private var showRename = false
    @State private var showHideConfirmation = false

    init(account: Account) {
        _viewModel = StateObject(wrappedValue: ChildWalletsViewModel(account: account))
    }

    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin24) {
                if viewModel.canCreateChildWallet {
                    if let createRequirementText = viewModel.createRequirementText {
                        AlertCardView(.init(text: createRequirementText, type: .caution, style: .inline))
                    }

                    ListSection {
                        ForEach(viewModel.items) { item in
                            row(item: item)
                        }
                    }
                } else {
                    PlaceholderViewNew(
                        icon: "warning_filled",
                        title: "暂不支持子钱包",
                        subtitle: "当前入口仅支持助记词钱包，私钥、观察钱包和 Passkey 钱包会保持主钱包模式。"
                    )
                }
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationTitle("子钱包")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    viewModel.createNextChildWallet()
                }) {
                    Image("plus")
                }
                .modifier(ConfirmationButtonStyle())
                .disabled(viewModel.createDisabled)
            }
        }
        .onChange(of: viewModel.errorText) { errorText in
            showError = errorText != nil
        }
        .alert("子钱包", isPresented: $showError) {
            Button("button.ok".localized) {
                viewModel.errorText = nil
            }
        } message: {
            Text(viewModel.errorText ?? "")
        }
        .alert("重命名子钱包", isPresented: $showRename) {
            TextField("子钱包名称", text: $viewModel.renameNameText)
            Button("button.cancel".localized, role: .cancel) {}
            Button("button.ok".localized) {
                viewModel.renamePendingChildWallet()
            }
        }
        .alert("隐藏子钱包", isPresented: $showHideConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("隐藏", role: .destructive) {
                viewModel.hidePendingChildWallet()
            }
        } message: {
            Text("隐藏后不会释放 Index，也不会影响助记词派生地址。")
        }
    }

    @ViewBuilder private func row(item: ChildWalletsViewModel.Item) -> some View {
        let cell = Cell(
                left: {
                    Image.checkbox(active: item.isActive)
                },
                middle: {
                    MultiText(title: item.title, subtitle: item.subtitle)
                },
                right: {
                    if item.isActive {
                        ThemeText("当前", style: .subheadSB, colorStyle: .yellow)
                    }
                },
                action: {
                    viewModel.select(item: item)
                }
            )

        if item.childWallet != nil {
            cell.contextMenu {
                Button("重命名") {
                    if viewModel.prepareRename(item: item) {
                        showRename = true
                    }
                }

                Button("隐藏", role: .destructive) {
                    if viewModel.prepareHide(item: item) {
                        showHideConfirmation = true
                    }
                }
            }
        } else {
            cell
        }
    }
}
