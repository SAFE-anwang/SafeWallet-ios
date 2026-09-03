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
            if !viewModel.hasLoadedItems {
                PlaceholderViewNew(icon: "no_data_48", title: "safe_dapp.empty".localized)
            } else {
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        searchField
                        if viewModel.isSearchResultEmpty {
                            PlaceholderViewNew(
                                icon: "no_data_48",
                                title: "safe_dapp.search_empty".localized,
                                layoutType: .middle,
                                additionalContent: { EmptyView() }
                            )
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            ListSection {
                                ForEach(items) { item in
                                    SafeDappItemView(
                                        item: item,
                                        editAction: {
                                            guard let editViewModel = SafeDappModule.editViewModel(info: item.info, currentLogo: item.logo) else { return }
                                            path.append(SafeDappManagerViewModel.DetailViewType(kind: .edit, viewModel: editViewModel))
                                        },
                                        removeAction: { removeTarget = item }
                                    )
                                }
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
    let editAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: .margin12) {
            logo

            VStack(alignment: .leading, spacing: 4) {
                Text(item.info.name)
                    .themeSubhead1(color: .themeLeah)
                    .lineLimit(1)

                Text(item.info.runUrl)
                    .themeCaption(color: .themeGray)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.info.description)
                    .themeCaption(color: .themeGray)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if item.info.isFrozen || item.logoMissing {
                    status
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: .margin8) {
                IconButton(icon: "edit_20", style: .secondary, size: .small, action: editAction)
                    .disabled(item.info.isFrozen)
                    .accessibilityLabel("SRC20_Info_Edit".localized)
                IconButton(icon: "trash", style: .secondary, size: .small, action: removeAction)
                    .accessibilityLabel("button.delete".localized)
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
    }

    @ViewBuilder private var logo: some View {
        Group {
            if let image = item.logo {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("safe-anwang_trx_32")
                    .resizable()
                    .scaledToFit()
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

}
