import SwiftUI

struct SafeDappManagerView: View {
    @StateObject var viewModel: SafeDappManagerViewModel
    @State private var path = NavigationPath()
    @State private var removeTarget: SafeDappViewItem?
    @Binding private var isPresented: Bool

    init(viewModel: SafeDappManagerViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack(path: $path) {
            ThemeView {
                ZStack {
                    content
                    if viewModel.operationState == .sending {
                        ProgressView()
                    }
                }
            }
            .navigationBarTitle("safe_dapp.manage".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { isPresented = false }) { Image("close") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.load() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.themeYellow)
                    }
                }
            }
            .navigationDestination(for: SafeDappManagerViewModel.DetailViewType.self) { type in
                switch type.kind {
                case .edit:
                    if let viewModel = type.viewModel as? SafeDappEditViewModel {
                        SafeDappEditView(viewModel: viewModel)
                    }
                case .logo:
                    if let viewModel = type.viewModel as? SafeDappLogoViewModel {
                        SafeDappLogoView(viewModel: viewModel)
                    }
                }
            }
            .alert(item: $viewModel.openAlert) { alert in
                if let url = alert.url {
                    return Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .default(Text("button.continue".localized)) {
                            viewModel.open(url: url)
                        },
                        secondaryButton: .cancel(Text("button.cancel".localized))
                    )
                }
                return Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("button.ok".localized)))
            }
            .alert("safe_dapp.remove_confirm".localized, isPresented: Binding(
                get: { removeTarget != nil },
                set: { if !$0 { removeTarget = nil } }
            ), actions: {
                Button("button.cancel".localized, role: .cancel) { removeTarget = nil }
                Button("button.delete".localized, role: .destructive) {
                    guard let target = removeTarget else { return }
                    viewModel.remove(item: target) { state in
                        switch state {
                        case .completed:
                            HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                        case let .failed(message):
                            HudHelper.instance.show(banner: .error(string: message))
                        default: ()
                        }
                    }
                    removeTarget = nil
                }
            })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.dataState {
        case .loading:
            ProgressView()
        case let .completed(items):
            if items.isEmpty {
                PlaceholderViewNew(icon: "no_data_48", title: "safe_dapp.empty".localized)
            } else {
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        searchField
                        ListSection {
                            ForEach(items) { item in
                                SafeDappItemView(
                                    item: item,
                                    openAction: { viewModel.prepareOpen(item: item) },
                                    editAction: {
                                        guard let editViewModel = SafeDappModule.editViewModel(info: item.info) else { return }
                                        path.append(SafeDappManagerViewModel.DetailViewType(kind: .edit, viewModel: editViewModel))
                                    },
                                    logoAction: {
                                        guard let logoViewModel = SafeDappModule.logoViewModel(info: item.info, currentLogo: item.logo) else { return }
                                        path.append(SafeDappManagerViewModel.DetailViewType(kind: .logo, viewModel: logoViewModel))
                                    },
                                    removeAction: { removeTarget = item }
                                )
                            }
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                }
            }
        case .failed:
            SyncErrorView { viewModel.load() }
        }
    }
}

private extension SafeDappManagerView {
    var searchField: some View {
        HStack(spacing: .margin8) {
            Image("search").icon()
            TextField("placeholder.search".localized, text: $viewModel.searchText)
                .foregroundColor(.themeLeah)
                .font(.themeBody)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image("trash_20").renderingMode(.template)
                }
                .buttonStyle(SecondaryCircleButtonStyle(style: .default))
            }
        }
        .padding(.horizontal, .margin16)
        .frame(height: 48)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }
}

private struct SafeDappItemView: View {
    let item: SafeDappViewItem
    let openAction: () -> Void
    let editAction: () -> Void
    let logoAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            HStack(spacing: .margin12) {
                logo
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.info.name)
                        .themeSubhead1(color: .themeLeah)
                    Text("ID: \(item.info.id.description)")
                        .themeSubhead2(color: .themeGray)
                }
                Spacer()
                status
            }
            value(title: SafeDappField.runUrl.title, value: item.info.runUrl)
            value(title: SafeDappField.contractAddr.title, value: item.contractAddress)
            value(title: "safe_dapp.fraud_count".localized, value: item.info.fraudNum.description)
            buttons
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
    }

    @ViewBuilder private var logo: some View {
        Group {
            if let image = item.logo {
                Image(uiImage: image).resizable()
            } else {
                Image("safe-anwang_trx_32").resizable().scaledToFit()
            }
        }
        .clipShape(Circle())
        .frame(width: .iconSize48, height: .iconSize48)
    }

    @ViewBuilder private var status: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if item.info.isFrozen {
                Text("safe_dapp.frozen".localized).themeCaption(color: .themeLucian)
            }
            if item.logoMissing {
                Text("safe_dapp.logo_missing".localized).themeCaption(color: .themeYellow)
            }
        }
    }

    @ViewBuilder private func value(title: String, value: String) -> some View {
        HStack(spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            Button(action: {
                UIPasteboard.general.string = value
                HudHelper.instance.show(banner: .copied)
            }) {
                Text(value)
                    .themeSubhead2(color: .themeLeah, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        SafeZoneItemActionGrid {
            SafeZoneItemActionButton(title: "safe_dapp.open".localized, action: openAction)
                .disabled(item.info.isFrozen)
            SafeZoneItemActionButton(title: "button.edit".localized, action: editAction)
                .disabled(item.info.isFrozen)
            SafeZoneItemActionButton(title: "safe_dapp.logo".localized, action: logoAction)
                .disabled(item.info.isFrozen)
            SafeZoneItemActionButton(title: "button.delete".localized, action: removeAction)
        }
    }
}
