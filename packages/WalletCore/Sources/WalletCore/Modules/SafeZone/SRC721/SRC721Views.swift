import BigInt
import SwiftUI
import UIKit

private struct SRC721LogoView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: SRC721LogoViewModel
    private let onSubmitted: () -> Void
    @State private var isShowingImagePicker = false
    @State private var isShowingConfirmation = false

    init(viewModel: SRC721LogoViewModel, onSubmitted: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        ThemeView {
            ZStack {
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            VStack(alignment: .leading, spacing: .margin8) {
                                Text(viewModel.record.name.isEmpty ? "SRC721" : viewModel.record.name)
                                    .themeSubhead1(color: .themeLeah)
                                Text(viewModel.record.contractAddress)
                                    .themeMicro(color: .themeGray)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, .margin16)
                            .padding(.vertical, .margin8)
                            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))

                            VStack(alignment: .leading, spacing: .margin8) {
                                Text("safe_zone.src721.section.logo".localized.uppercased())
                                    .themeSubhead1(color: .themeLeah)
                                    .padding(.top, .margin16)
                                HStack(spacing: .margin16) {
                                    Group {
                                        if let image = viewModel.selectedImage {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else {
                                            Image(systemName: "photo").resizable().scaledToFit().padding(.margin12)
                                                .foregroundColor(.themeGray)
                                        }
                                    }
                                    .frame(width: .iconSize48, height: .iconSize48)
                                    .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous))
                                    Button("safe_zone.src721.action.choose_logo".localized) {
                                        isShowingImagePicker = true
                                    }
                                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                                }
                                .padding(.horizontal, .margin16)
                                .padding(.vertical, .margin8)
                                .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
                                .modifier(CautionBorder(cautionState: $viewModel.logoCautionState))
                                .modifier(CautionPrompt(cautionState: $viewModel.logoCautionState))
                            }
                            if let fee = viewModel.fee {
                                HStack(spacing: .margin8) {
                                    Image("circle_warning_24").themeIcon(color: .themeLeah)
                                    Text("safe_zone.src721.logo_fee".localized(fee.safe4FormattedAmount))
                                        .themeSubhead2(color: .themeLeah)
                                    Spacer()
                                }
                                .padding(.horizontal, .margin16)
                                .padding(.vertical, .margin8)
                                .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
                            }
                        }
                        .padding(.init(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    }
                } bottomContent: {
                    Button("safe_zone.src721.action.set_logo".localized) {
                        isShowingConfirmation = true
                    }
                    .disabled(viewModel.sendState != .ready)
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                }
                if viewModel.sendState == .sending { ProgressView() }
            }
        }
        .navigationTitle("safe_zone.src721.section.logo".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(selectedImage: $viewModel.selectedImage)
        }
        .alert("safe_zone.src721.confirm.set_logo".localized, isPresented: $isShowingConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("button.confirm".localized) {
                viewModel.upload { state in
                    switch state {
                    case .completed:
                        HudHelper.instance.show(banner: .success(string: "safe_zone.src721.operation.confirmed".localized))
                        onSubmitted()
                        presentationMode.wrappedValue.dismiss()
                    case .failed:
                        HudHelper.instance.show(banner: .error(string: viewModel.operationError ?? "safe_zone.src721.operation.failure".localized))
                    default: break
                    }
                }
            }
        } message: {
            Text("safe_zone.src721.confirm.set_logo.details".localized)
        }
    }
}

struct SRC721DeployView: View {
    @StateObject private var viewModel: SRC721DeployViewModel
    @Binding private var isPresented: Bool
    @State private var isShowingConfirmation = false
    @FocusState private var focusedField: SRC721DeployField?

    init(viewModel: SRC721DeployViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ZStack {
                    BottomGradientWrapper {
                        ScrollViewReader { proxy in
                            ScrollableThemeView {
                                VStack(spacing: .margin8) {
                                    typeView
                                    hintView
                                    input(title: "safe_zone.src721.field.name".localized, text: $viewModel.name, prompt: "safe_zone.src721.placeholder.name", field: .name, caution: $viewModel.nameCautionState, keyboard: .default) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.nameMaxUTF8Length) }.id(SRC721DeployField.name)
                                    input(title: "safe_zone.src721.field.symbol".localized, text: $viewModel.symbol, prompt: "safe_zone.src721.placeholder.symbol", field: .symbol, caution: $viewModel.symbolCautionState, keyboard: .default) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.symbolMaxUTF8Length) }.id(SRC721DeployField.symbol)
                                    input(title: "safe_zone.src721.field.base_uri".localized, text: $viewModel.baseURI, prompt: "safe_zone.src721.placeholder.base_uri", field: .baseURI, caution: $viewModel.baseURICautionState, keyboard: .URL) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.baseURIMaxUTF8Length) }.id(SRC721DeployField.baseURI)
                                    input(title: "safe_zone.src721.field.max_supply".localized, text: $viewModel.maxSupply, prompt: "safe_zone.src721.placeholder.max_supply", field: .maxSupply, caution: $viewModel.maxSupplyCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }.id(SRC721DeployField.maxSupply)
                                    input(title: "safe_zone.src721.field.mint_price".localized, text: $viewModel.mintPrice, prompt: "safe_zone.src721.placeholder.mint_price", field: .mintPrice, caution: $viewModel.mintPriceCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }.id(SRC721DeployField.mintPrice)
                                }
                                .padding(.init(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { dismissDeployKeyboard() }
                            .onChange(of: viewModel.validationRequestID) { _, _ in
                                guard let field = viewModel.invalidField else { return }
                                focusedField = field
                                DispatchQueue.main.async {
                                    withAnimation { proxy.scrollTo(field, anchor: .center) }
                                }
                            }
                        }
                    } bottomContent: {
                        Button("safe_zone.src721.action.deploy".localized) {
                            focusedField = nil
                            dismissSRC721Keyboard()
                            if viewModel.validateForSubmit() {
                                isShowingConfirmation = true
                            }
                        }
                        .disabled(viewModel.sendState == .sending)
                        .buttonStyle(PrimaryButtonStyle(style: .yellow))
                    }
                    if viewModel.sendState == .sending { ProgressView() }
                }
            }
            .navigationTitle("safe_zone.src721.deploy".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { isPresented = false } label: { Image("close") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("button.done".localized) { dismissDeployKeyboard() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissDeployKeyboard() }
            .alert("safe_zone.src721.confirm.deploy".localized, isPresented: $isShowingConfirmation) {
                Button("button.cancel".localized, role: .cancel) {}
                Button("button.confirm".localized) {
                    focusedField = nil
                    dismissSRC721Keyboard()
                    viewModel.deploy()
                }
            } message: {
                Text(viewModel.type.title)
            }
            .alert("safe_zone.src721.error.title".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil && viewModel.sendState == .failed },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("button.ok".localized, role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.sendState) { _, state in
                if state == .completed {
                    isPresented = false
                }
            }
            .onChange(of: viewModel.submissionID) { _, _ in
                HudHelper.instance.show(banner: .success(string: "safe_zone.src721.deploy.success".localized))
            }
        }
    }

    private func dismissDeployKeyboard() {
        focusedField = nil
        dismissSRC721Keyboard()
    }

    private var typeView: some View {
        VStack(spacing: .margin12) {
            SectionHeader(text: "safe_zone.src721.field.type".localized)
            ForEach([SRC721ContractType.standard, .burnable], id: \.self) { type in
                Button { viewModel.type = type } label: {
                    HStack(spacing: .margin8) {
                        Image(viewModel.type == type ? "checkbox_active_24" : "checkbox_diactive_24")
                        Text(type.title).themeSubhead2()
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    private var hintView: some View {
        Text(viewModel.type == .standard ? "safe_zone.src721.deploy.hint.standard".localized : "safe_zone.src721.deploy.hint.burnable".localized)
            .themeSubhead2(color: .themeGray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin12)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    private func input(title: String, text: Binding<String>, prompt: String, field: SRC721DeployField, caution: Binding<CautionState>, keyboard: UIKeyboardType, transform: @escaping (String) -> String?) -> some View {
        let limitedText = Binding<String>(
            get: { text.wrappedValue },
            set: { if let value = transform($0) { text.wrappedValue = value } }
        )
        return VStack(alignment: .leading, spacing: .margin8) {
            SectionHeader(text: title)
            HStack(alignment: .top, spacing: .margin8) {
                TextField("", text: limitedText, prompt: Text(prompt.localized).foregroundColor(.themeGray), axis: .vertical)
                    .foregroundColor(.themeLeah)
                    .font(.themeBody)
                    .keyboardType(keyboard)
                    .lineLimit(1...)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                if !limitedText.wrappedValue.isEmpty {
                    Button { limitedText.wrappedValue = "" } label: { Image("trash_20").renderingMode(.template) }
                        .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: caution))
            .modifier(CautionPrompt(cautionState: caution))
        }
    }

    private struct SectionHeader: View {
        let text: String
        var body: some View { Text(text.uppercased()).themeSubhead1(color: .themeLeah).padding(.top, .margin8) }
    }
}

struct SRC721ManagerView: View {
    @Binding private var isPresented: Bool

    init(viewModel _: SRC721ManagerViewModel, isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ScrollableThemeView {
                    ListSection {
                        NavigationLink {
                            if let viewModel = SRC721Module.managerViewModel() {
                                SRC721ContractsView(viewModel: viewModel)
                            }
                        } label: {
                            managementRow(title: "safe_zone.src721.my_contracts".localized, icon: "doc.text")
                        }
                        NavigationLink {
                            if let viewModel = SRC721Module.walletAssetsViewModel() {
                                SRC721WalletAssetsView(viewModel: viewModel)
                            }
                        } label: {
                            managementRow(title: "safe_zone.src721.my_nfts".localized, icon: "photo.on.rectangle")
                        }
                    }
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin12)
                }
            }
            .navigationTitle("safe_zone.src721.manager".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { isPresented = false } label: { Image("close") }
                }
            }
        }
    }

    private func managementRow(title: String, icon: String) -> some View {
        HStack(spacing: .margin12) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundColor(.themeLeah)
            Text(title).themeSubhead1(color: .themeLeah)
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.themeGray)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
    }
}

private struct SRC721ContractsView: View {
    @StateObject private var viewModel: SRC721ManagerViewModel

    init(viewModel: SRC721ManagerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            VStack(spacing: .margin8) {
                Text("safe_zone.src721.manager.hint".localized)
                    .themeSubhead2(color: .themeGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin12)
                if viewModel.records.isEmpty && viewModel.isRefreshing {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.records.isEmpty, let loadError = viewModel.loadError {
                    Spacer()
                    VStack(spacing: .margin12) {
                        Text(loadError)
                            .themeSubhead2(color: .themeRed, alignment: .center)
                        Button("safe_zone.src721.action.retry_nfts".localized) { viewModel.refresh() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, .margin16)
                    Spacer()
                } else if viewModel.records.isEmpty {
                    Spacer()
                    PlaceholderViewNew(icon: "no_data_48", title: "safe_zone.src721.empty".localized)
                    Spacer()
                } else {
                    if let loadError = viewModel.loadError {
                        Text(loadError)
                            .themeSubhead2(color: .themeAndy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, .margin16)
                    }
                    ScrollableThemeView {
                        ListSection {
                            ForEach(viewModel.records) { record in
                                SRC721ContractRow(
                                    record: record,
                                    state: viewModel.contractStates[record.contractAddress.lowercased()],
                                    isLoadingState: viewModel.loadingContractAddresses.contains(record.contractAddress.lowercased()),
                                    hasPendingTokenOperation: viewModel.pendingTokenContractAddresses.contains(record.contractAddress.lowercased()),
                                    onDelete: { viewModel.removeFromList(record) }
                                )
                            }
                        }
                        .padding(.horizontal, .margin16)
                        .padding(.bottom, .margin32)
                    }
                }
            }
        }
        .navigationTitle("safe_zone.src721.my_contracts".localized)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { viewModel.refresh() }
    }
}

private struct SRC721WalletAssetsView: View {
    @StateObject private var viewModel: SRC721WalletAssetsViewModel

    init(viewModel: SRC721WalletAssetsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            VStack(spacing: .margin8) {
                Text("safe_zone.src721.wallet_nfts.hint".localized)
                    .themeSubhead2(color: .themeGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin12)

                if viewModel.isTruncated {
                    Text("safe_zone.src721.wallet_nfts.truncated".localized)
                        .themeSubhead2(color: .themeAndy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .margin16)
                }
                if viewModel.hasLoadErrors && !viewModel.collections.isEmpty {
                    Text("safe_zone.src721.wallet_nfts.partial_error".localized)
                        .themeSubhead2(color: .themeAndy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .margin16)
                }

                switch viewModel.dataState {
                case .loading:
                    Spacer()
                    ProgressView()
                    Spacer()
                case let .failed(message):
                    Spacer()
                    VStack(spacing: .margin12) {
                        Text(message)
                            .themeSubhead2(color: .themeRed, alignment: .center)
                        Button("safe_zone.src721.action.retry_nfts".localized) { viewModel.refresh() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, .margin16)
                    Spacer()
                case let .unavailable(message):
                    Spacer()
                    PlaceholderViewNew(icon: "no_data_48", title: message)
                    Spacer()
                case .completed:
                    if viewModel.collections.isEmpty {
                        Spacer()
                        PlaceholderViewNew(icon: "no_data_48", title: "safe_zone.src721.empty.wallet_nfts".localized)
                        Spacer()
                    } else {
                        ScrollableThemeView {
                            ListSection {
                                ForEach(viewModel.collections) { collection in
                                    NavigationLink {
                                        SRC721WalletCollectionView(collection: collection, onAssetsChanged: viewModel.refresh)
                                    } label: {
                                        SRC721WalletCollectionRow(collection: collection)
                                    }
                                }
                            }
                            .padding(.horizontal, .margin16)
                            .padding(.bottom, .margin32)
                        }
                    }
                }
            }
        }
        .navigationTitle("safe_zone.src721.my_nfts".localized)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { viewModel.refresh() }
    }
}

private struct SRC721WalletCollectionRow: View {
    let collection: SRC721WalletCollection

    var body: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            HStack(alignment: .firstTextBaseline) {
                Text(collection.displayName)
                    .themeSubhead1(color: .themeLeah)
                Spacer()
                Text("safe_zone.src721.field.wallet_owned_count".localized(collection.assets.count.description))
                    .themeMicro(color: .themeGray, alignment: .trailing)
            }
            Text("\("safe_zone.src721.field.symbol".localized): \(collection.contract.symbol)")
                .themeSubhead2(color: .themeGray)
            Text("\("safe_zone.src721.field.contract".localized): \(collection.contract.contractAddress.shortened)")
                .themeMicro(color: .blue)
                .lineLimit(1)
            HStack(alignment: .bottom) {
                if collection.assets.contains(where: { $0.pendingOperation != nil }) {
                    Text("safe_zone.src721.status.token_operation_pending".localized)
                        .themeMicro(color: .themeAndy)
                }
                Spacer()
                if collection.contract.contractType == .burnable {
                    SRC721BurnableBadge()
                }
            }
//                .truncationMode(.middle)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
    }
}

private struct SRC721WalletCollectionView: View {
    let collection: SRC721WalletCollection
    let onAssetsChanged: () -> Void
    @State private var assets: [SRC721WalletAsset]

    init(collection: SRC721WalletCollection, onAssetsChanged: @escaping () -> Void) {
        self.collection = collection
        self.onAssetsChanged = onAssetsChanged
        _assets = State(initialValue: collection.assets)
    }

    private var displayedCollection: SRC721WalletCollection {
        SRC721WalletCollection(contract: collection.contract, assets: assets)
    }

    var body: some View {
        ThemeView {
            ScrollableThemeView {
                VStack(spacing: .margin16) {
                    ListSection {
                        SRC721WalletCollectionRow(collection: displayedCollection)
                    }

                    VStack(alignment: .leading, spacing: .margin8) {
                        Text("safe_zone.src721.section.my_nfts".localized.uppercased())
                            .themeSubhead1(color: .themeLeah)
                        if assets.isEmpty {
                            PlaceholderViewNew(icon: "no_data_48", title: "safe_zone.src721.empty.my_nfts".localized)
                        } else {
                            ListSection {
                                ForEach(assets) { asset in
                                    NavigationLink {
                                        SRC721WalletAssetDetailRoute(
                                            asset: asset,
                                            onPending: { pendingAsset, operation in
                                                assets = assets.map {
                                                    $0.id == pendingAsset.id
                                                        ? SRC721WalletAsset(contract: $0.contract, token: $0.token, pendingOperation: operation)
                                                        : $0
                                                }
                                                onAssetsChanged()
                                            },
                                            onChanged: { changedAsset in
                                            assets.removeAll { $0.id == changedAsset.id }
                                            onAssetsChanged()
                                            }
                                        )
                                    } label: {
                                        SRC721WalletCollectionTokenRow(asset: asset)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, .margin16)
                .padding(.vertical, .margin12)
                .padding(.bottom, .margin32)
            }
        }
        .navigationTitle(collection.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SRC721WalletCollectionTokenRow: View {
    let asset: SRC721WalletAsset

    var body: some View {
        HStack(spacing: .margin12) {
            ThemeImage(
                ComponentImage.remote(url: asset.token.imageURL ?? "", placeholder: "placeholder_nft_32", size: CGSize(width: 40, height: 40)),
                size: CGSize(width: 40, height: 40),
                colorStyle: nil
            )
            .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous))
            Text("safe_zone.src721.nft_detail".localized(asset.token.tokenId.description))
                .themeSubhead1(color: .themeLeah)
            Spacer()
            if let pendingOperation = asset.pendingOperation {
                Text(pendingOperation == .burn
                    ? "safe_zone.src721.status.burn_pending".localized
                    : "safe_zone.src721.status.transfer_pending".localized)
                    .themeMicro(color: .themeAndy, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
    }
}

private struct SRC721ContractRow: View {
    let record: SRC721ContractRecord
    let state: SRC721ContractSupplyState?
    let isLoadingState: Bool
    let hasPendingTokenOperation: Bool
    let onDelete: () -> Void
    @State private var isShowingDeleteConfirmation = false

    init(record: SRC721ContractRecord, state: SRC721ContractSupplyState?, isLoadingState: Bool = false, hasPendingTokenOperation: Bool = false, onDelete: @escaping () -> Void) {
        self.record = record
        self.state = state
        self.isLoadingState = isLoadingState
        self.hasPendingTokenOperation = hasPendingTokenOperation
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            VStack(alignment: .leading, spacing: .margin8) {
                HStack(alignment: .center) {
                    Text(contractDisplayName)
                        .themeSubhead1(color: .themeLeah)
                        .lineLimit(1)
                    Spacer(minLength: .margin8)
                    if record.contractType == .burnable { SRC721BurnableBadge() }
                }
                Text(record.contractAddress.shortened)
                    .themeMicro(color: .themeAndy)
                    .lineLimit(1)
                if isLoadingState {
                    HStack(spacing: .margin4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("safe_zone.src721.status.syncing".localized)
                            .themeSubhead2(color: .themeGray)
                    }
                } else {
                    HStack(spacing: .margin16) {
                        contractMetric("safe_zone.src721.list.minted".localized, mintedCount?.description ?? "-")
                        contractMetric("safe_zone.src721.list.remaining".localized, state?.remainSupply.description ?? "-")
                        if record.contractType.canBurn {
                            contractMetric("safe_zone.src721.list.burned".localized, state?.burnedCount?.description ?? "-")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: .margin8) {
                NavigationLink {
                    SRC721ContractQuickActionRoute(record: record, action: .mint)
                } label: {
                    Text("safe_zone.src721.action.mint_short".localized)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(SRC721ContractRowActionStyle())
                .disabled(!record.isReadOnly && record.isPending)
                .frame(maxWidth: .infinity)

                if record.contractType.canBurn {
                    NavigationLink {
                        SRC721BurnTokenIDRoute(record: record)
                    } label: {
                        Text("safe_zone.src721.action.burn".localized)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(SRC721ContractRowActionStyle())
                    .disabled(record.isPending || hasPendingTokenOperation)
                    .frame(maxWidth: .infinity)
                }

                Button("safe_zone.src721.action.remove".localized) {
                    isShowingDeleteConfirmation = true
                }
                .buttonStyle(SRC721ContractRowActionStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .background {
            NavigationLink { SRC721ContractDetailRoute(record: record) } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .alert("safe_zone.src721.confirm.remove".localized, isPresented: $isShowingDeleteConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("safe_zone.src721.action.remove".localized, role: .destructive, action: onDelete)
        } message: {
            Text("safe_zone.src721.confirm.remove.details".localized)
        }
    }

    private var mintedCount: BigUInt? {
        guard let state else { return nil }
        return state.totalSupply + (state.burnedCount ?? 0)
    }

    private var contractDisplayName: String {
        let name = record.name.isEmpty ? "SRC721" : record.name
        return record.symbol.isEmpty ? name : "\(name) (\(record.symbol))"
    }

    private func contractMetric(_ title: String, _ value: String) -> some View {
        Text("\(title) \(value)")
            .textSubhead2(color: .themeGray)
            .lineLimit(1)
    }
}

private struct SRC721BurnTokenIDRoute: View {
    let record: SRC721ContractRecord
    @State private var viewModel: SRC721ContractDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SRC721BurnTokenIDView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = SRC721Module.detailViewModel(record: record)
        }
    }
}

private struct SRC721BurnTokenIDView: View {
    @ObservedObject var viewModel: SRC721ContractDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tokenId = ""
    @FocusState private var isInputFocused: Bool
    @State private var initialSubmissionID: UUID?

    private var isSubmitting: Bool { viewModel.isSubmittingOperation }

    private var isValidTokenId: Bool {
        (try? SRC721Validation.amount(tokenId, field: "safe_zone.src721.field.token_id".localized, allowZero: true)) != nil
    }

    private var tokenIdBinding: Binding<String> {
        Binding(
            get: { tokenId },
            set: { value in
                if let normalized = SRC721Validation.validDecimalInput(value) {
                    tokenId = normalized
                }
            }
        )
    }

    var body: some View {
        ThemeView {
            ZStack {
                ScrollableThemeView {
                    VStack(alignment: .leading, spacing: .margin16) {
                        Text("safe_zone.src721.burn.dialog.description".localized)
                            .themeBody(color: .themeLeah)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: .margin8) {
                            TextField("safe_zone.src721.burn.dialog.placeholder".localized, text: tokenIdBinding)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.themeLeah)
                                .tint(.themeLeah)
                                .focused($isInputFocused)
                            Button("button.paste".localized) {
                                guard let value = UIPasteboard.general.string else { return }
                                tokenIdBinding.wrappedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .foregroundColor(.themeLeah)
                            .padding(.horizontal, .margin12)
                            .padding(.vertical, .margin8)
                            .background(Color.themeBlade)
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, .margin16)
                        .frame(height: 50)
                        .background(Color.themeLawrence)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.themeBlade, lineWidth: .heightOneDp))

                        Button("button.confirm".localized) {
                            dismissSRC721Keyboard()
                            viewModel.burn(tokenId: tokenId)
                        }
                        .buttonStyle(PrimaryButtonStyle(style: .yellow))
                        .frame(maxWidth: .infinity)
                        .disabled(!isValidTokenId || isSubmitting)
                    }
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin16)
                    .padding(.bottom, .margin32)
                }
                if isSubmitting { ProgressView() }
            }
        }
        .navigationTitle("safe_zone.src721.action.burn".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            initialSubmissionID = viewModel.submissionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isInputFocused = true }
        }
        .onChange(of: viewModel.submissionID) { _, newValue in
            guard let initialSubmissionID, newValue != initialSubmissionID else { return }
            self.initialSubmissionID = newValue
            dismiss()
            HudHelper.instance.show(banner: .success(string: "safe_zone.src721.operation.confirmed".localized))
        }
        .onChange(of: viewModel.operationMessage) { _, message in
            guard let message, viewModel.operationState == .failed else { return }
            HudHelper.instance.show(banner: .error(string: message))
        }
    }
}

private struct SRC721ContractRowActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.themeCaptionSB)
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .padding(.horizontal, .margin8)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return .themeAndy }
        return isPressed ? .themeDark.opacity(0.7) : .themeDark
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return .themeBlade }
        return isPressed ? .themeYellow50 : .themeYellow
    }
}

private enum SRC721ContractQuickAction {
    case mint
    case burn
}

private struct SRC721ContractQuickActionRoute: View {
    let record: SRC721ContractRecord
    let action: SRC721ContractQuickAction
    @State private var viewModel: SRC721ContractDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SRC721ContractQuickActionView(record: record, action: action, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = SRC721Module.detailViewModel(record: record)
        }
    }
}

private struct SRC721ContractQuickActionView: View {
    let record: SRC721ContractRecord
    let action: SRC721ContractQuickAction
    @ObservedObject var viewModel: SRC721ContractDetailViewModel
    @State private var recipient = ""
    @State private var amount = ""
    @State private var tokenId = ""
    @State private var isShowingConfirmation = false

    var body: some View {
        ThemeView {
            ZStack {
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        Text(record.name.isEmpty ? "SRC721" : record.name)
                            .themeSubhead1(color: .themeLeah)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if action == .mint {
                            mintSupplySummary
                            SRC721AddressInput(title: "safe_zone.src721.field.recipient".localized, prompt: "safe_zone.src721.placeholder.recipient", text: $recipient, caution: $viewModel.mintRecipientCautionState)
                            TextField("safe_zone.src721.field.amount".localized, text: $amount)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            Button("safe_zone.src721.action.admin_mint".localized) {
                                guard viewModel.validateMint(to: recipient, amount: amount, admin: true) else { return }
                                isShowingConfirmation = true
                            }
                            .buttonStyle(PrimaryButtonStyle(style: .yellow))
                            .disabled(!viewModel.canManage || !viewModel.isContractStateReady || viewModel.isSubmittingOperation)
                        } else {
                            TextField("safe_zone.src721.field.token_id".localized, text: $tokenId)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            Button("safe_zone.src721.action.burn".localized) {
                                guard BigUInt(tokenId) != nil else { return }
                                isShowingConfirmation = true
                            }
                            .buttonStyle(PrimaryButtonStyle(style: .yellow))
                            .disabled(!viewModel.canTransact || viewModel.isSubmittingOperation)
                        }
                    }
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin16)
                }
                if viewModel.isSubmittingOperation { ProgressView() }
            }
        }
        .navigationTitle(action == .mint ? "safe_zone.src721.action.admin_mint".localized : "safe_zone.src721.action.burn".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert(action == .mint ? "safe_zone.src721.confirm.mint".localized : "safe_zone.src721.confirm.burn".localized, isPresented: $isShowingConfirmation) {
            Button("button.confirm".localized, role: .destructive) {
                if action == .mint {
                    viewModel.mint(to: recipient, amount: amount, admin: true)
                } else {
                    viewModel.burn(tokenId: tokenId)
                }
            }
        } message: {
            Text(action == .mint
                 ? "safe_zone.src721.confirm.admin_mint".localized
                 : "safe_zone.src721.confirm.burn.details".localized)
        }
        .onChange(of: viewModel.submissionID) { _, _ in
            HudHelper.instance.show(banner: .success(string: "safe_zone.src721.operation.confirmed".localized))
        }
        .alert("safe_zone.src721.operation.failure".localized, isPresented: Binding(
            get: { viewModel.operationState == .failed && viewModel.operationMessage != nil },
            set: { if !$0 { viewModel.operationMessage = nil } }
        )) {
            Button("button.ok".localized, role: .cancel) { viewModel.operationMessage = nil }
        } message: {
            Text(viewModel.operationMessage ?? "")
        }
    }

    @ViewBuilder private var mintSupplySummary: some View {
        if let state = viewModel.contractState {
            VStack(alignment: .leading, spacing: .margin8) {
                supplyMetric("safe_zone.src721.list.minted".localized, (state.totalSupply + (state.burnedCount ?? 0)).description)
                supplyMetric("safe_zone.src721.field.supply".localized, "\(state.totalSupply) / \(state.maxSupply)")
                supplyMetric("safe_zone.src721.field.burned_count".localized, state.burnedCount?.description ?? "-")
                supplyMetric("safe_zone.src721.field.remain".localized, state.remainSupply.description)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin12)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
        } else if case .loading = viewModel.dataState {
            HStack {
                ProgressView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin12)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
        } else {
            HStack(alignment: .top, spacing: .margin8) {
                Text(viewModel.refreshErrorMessage ?? "safe_zone.src721.error.contract_state_unavailable".localized)
                    .themeSubhead2(color: .themeRed)
                Spacer()
                Button("button.retry".localized) { viewModel.refresh() }
                    .themeSubhead2(color: .themeLeah)
                    .disabled(viewModel.isRefreshing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin12)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
        }
    }

    private func supplyMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            Spacer()
            Text(value).themeSubhead2(color: .themeLeah)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SRC721BurnableBadge: View {
    var body: some View {
        BadgeViewNew("Burnable", mode: .transparent, colorStyle: .secondary)
    }
}

private struct SRC721ContractDetailRoute: View {
    let record: SRC721ContractRecord
    let selectedTokenId: BigUInt?
    @State private var viewModel: SRC721ContractDetailViewModel?

    init(record: SRC721ContractRecord, selectedTokenId: BigUInt? = nil) {
        self.record = record
        self.selectedTokenId = selectedTokenId
    }

    var body: some View {
        Group {
            if let viewModel {
                SRC721ContractDetailView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let detailViewModel = SRC721Module.detailViewModel(record: record)
            viewModel = detailViewModel
            if let selectedTokenId {
                detailViewModel?.loadToken(tokenId: selectedTokenId)
            }
        }
    }
}

private struct SRC721WalletAssetDetailRoute: View {
    let asset: SRC721WalletAsset
    let onPending: (SRC721WalletAsset, SRC721TransactionOperation?) -> Void
    let onChanged: (SRC721WalletAsset) -> Void
    @State private var viewModel: SRC721ContractDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SRC721WalletAssetDetailView(asset: asset, viewModel: viewModel, onPending: onPending, onChanged: onChanged)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let detailViewModel = SRC721Module.detailViewModel(record: asset.contract)
            viewModel = detailViewModel
            detailViewModel?.loadToken(tokenId: asset.token.tokenId, showError: false)
        }
    }
}

private struct SRC721WalletAssetDetailView: View {
    let asset: SRC721WalletAsset
    let onPending: (SRC721WalletAsset, SRC721TransactionOperation?) -> Void
    let onChanged: (SRC721WalletAsset) -> Void
    @StateObject private var viewModel: SRC721ContractDetailViewModel
    @State private var approvedAddress = ""
    @State private var recipient = ""
    @State private var isShowingBurnConfirmation = false
    @Environment(\.presentationMode) private var presentationMode

    init(
        asset: SRC721WalletAsset,
        viewModel: SRC721ContractDetailViewModel,
        onPending: @escaping (SRC721WalletAsset, SRC721TransactionOperation?) -> Void,
        onChanged: @escaping (SRC721WalletAsset) -> Void
    ) {
        self.asset = asset
        self.onPending = onPending
        self.onChanged = onChanged
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            detailContent
        }
        .navigationTitle("safe_zone.src721.nft_detail".localized(asset.token.tokenId.description))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.loadToken(tokenId: asset.token.tokenId, showError: false)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingToken || viewModel.operationState == .sending)
                .accessibilityLabel("safe_zone.src721.action.refresh_nft".localized)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button.done".localized) { dismissSRC721Keyboard() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissSRC721Keyboard() }
        .refreshable { viewModel.loadToken(tokenId: asset.token.tokenId, showError: false) }
        .overlay { if viewModel.isSubmittingOperation { ProgressView() } }
        .onChange(of: viewModel.burnedTokenId) { _, tokenId in
            guard tokenId == asset.token.tokenId else { return }
            presentationMode.wrappedValue.dismiss()
            DispatchQueue.main.async {
                onChanged(asset)
            }
        }
        .onChange(of: viewModel.operationHashes) { _, _ in
            guard let operation = viewModel.pendingTokenOperation else { return }
            onPending(asset, operation)
        }
        .onChange(of: viewModel.submissionID) { _, _ in
            HudHelper.instance.show(banner: .success(string: "已提交，等待区块确认"))
            guard viewModel.pendingTokenOperation == .transfer else { return }
            onPending(asset, .transfer)
            presentationMode.wrappedValue.dismiss()
        }
        .alert(operationAlertTitle, isPresented: Binding(
            get: { viewModel.operationMessage != nil && viewModel.operationState == .failed },
            set: { if !$0 { viewModel.operationMessage = nil } }
        )) {
            if !viewModel.operationHashes.isEmpty {
                Button("button.copy".localized) {
                    CopyHelper.copyAndNotify(value: viewModel.operationHashes.joined(separator: "\n"))
                    viewModel.operationMessage = nil
                }
            }
            Button("button.ok".localized, role: .cancel) { viewModel.operationMessage = nil }
        } message: {
            Text(operationAlertMessage)
        }
        .alert("safe_zone.src721.confirm.burn".localized, isPresented: $isShowingBurnConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("safe_zone.src721.action.burn".localized, role: .destructive) {
                dismissSRC721Keyboard()
                viewModel.burn()
            }
        } message: {
            Text("safe_zone.src721.confirm.burn.details".localized)
        }
    }

    private var detailContent: some View {
        ScrollableThemeView {
            VStack(spacing: .margin8) {
                if let imageURL = asset.token.imageURL, !imageURL.isEmpty {
                    ThemeImage(
                        ComponentImage.remote(url: imageURL, placeholder: "placeholder_nft_32", size: CGSize(width: 240, height: 240)),
                        size: CGSize(width: 240, height: 240),
                        colorStyle: nil
                    )
                    .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous))
                }
                section(title: "safe_zone.src721.section.nft_details".localized) {
                    detailRow("safe_zone.src721.field.name".localized, asset.contract.name.isEmpty ? "SRC721" : asset.contract.name)
                    detailRow("safe_zone.src721.field.symbol".localized, asset.contract.symbol)
                    detailRow("safe_zone.src721.field.token_id".localized, asset.token.tokenId.description)
                    detailRow("safe_zone.src721.field.contract".localized, asset.contract.contractAddress, copyValue: asset.contract.contractAddress)
                    detailRow("safe_zone.src721.field.token_uri".localized, tokenURI)
                    if let token = viewModel.tokenState {
                        detailRow("safe_zone.src721.field.owner".localized, token.ownerAddress, copyValue: token.ownerAddress)
//                        detailRow("safe_zone.src721.field.approved".localized, token.approvedAddress)
//                        detailRow(
//                            "safe_zone.src721.field.operator_status".localized,
//                            token.isApprovedForAll
//                                ? "safe_zone.src721.status.authorized".localized
//                                : "safe_zone.src721.status.not_authorized".localized
//                        )
                    }
                }

                section(title: "safe_zone.src721.section.nft_actions".localized) {
                    if viewModel.tokenOperationPending {
                        Text("safe_zone.src721.status.token_operation_pending".localized)
                            .themeSubhead2(color: .themeAndy)
                    }
                    if viewModel.isLoadingToken {
                        tokenStateStatus
                    } else if viewModel.tokenState != nil {
                        Text(viewModel.canTransferLoadedToken ? "safe_zone.src721.status.token_operable".localized : "safe_zone.src721.status.token_read_only".localized)
                            .themeSubhead2(color: viewModel.canTransferLoadedToken ? .themeGreen : .themeGray)
                    } else {
                        tokenStateStatus
                    }

                    VStack(spacing: .margin8) {
//                        SRC721AddressInput(
//                            title: "safe_zone.src721.field.approved".localized,
//                            prompt: "safe_zone.src721.placeholder.recipient",
//                            text: $approvedAddress,
//                            caution: $viewModel.tokenRecipientCautionState
//                        )
//                        actionButton("safe_zone.src721.action.approve".localized) {
//                            guard viewModel.validateTokenOperation(recipient: approvedAddress, allowZeroRecipient: true) else { return }
//                            viewModel.approve(to: approvedAddress)
//                        }
//                        .disabled(!viewModel.canTransact || !viewModel.canApproveLoadedToken || viewModel.operationState == .sending || viewModel.tokenOperationPending)

                        SRC721AddressInput(
                            title: "safe_zone.src721.field.recipient".localized,
                            prompt: "safe_zone.src721.placeholder.recipient",
                            text: $recipient,
                            caution: $viewModel.tokenRecipientCautionState
                        )
                        HStack(spacing: .margin8) {
                            actionButton("safe_zone.src721.action.transfer".localized) {
                                guard viewModel.validateTokenOperation(recipient: recipient, allowZeroRecipient: false) else { return }
                                viewModel.transfer(to: recipient) { succeeded in
                                    if succeeded {
                                        onChanged(asset)
                                    } else {
                                        onPending(asset, nil)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(!viewModel.canTransact || !viewModel.canTransferLoadedToken || viewModel.operationState == .sending || viewModel.tokenOperationPending)

                            if asset.contract.contractType == .burnable {
                                actionButton("safe_zone.src721.action.burn".localized) {
                                    guard viewModel.validateTokenIdInput() else { return }
                                    isShowingBurnConfirmation = true
                                }
                                .frame(maxWidth: .infinity)
                                .disabled(!viewModel.canTransact || !viewModel.canBurnLoadedToken || viewModel.operationState == .sending || viewModel.tokenOperationPending)
                            }
                        }
                    }
                    .disabled(viewModel.tokenState == nil || viewModel.isLoadingToken)
                    .opacity(viewModel.tokenState == nil || viewModel.isLoadingToken ? 0.65 : 1)
                }
            }
            .padding(.init(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissSRC721Keyboard() }
    }

    private var tokenURI: String {
        viewModel.tokenState?.tokenURI ?? asset.token.tokenURI ?? "safe_zone.src721.metadata.unavailable".localized
    }

    @ViewBuilder private var tokenStateStatus: some View {
        if viewModel.isLoadingToken {
            HStack(spacing: .margin8) {
                ProgressView()
            }
        } else if viewModel.tokenLoadError != nil {
            HStack(alignment: .top, spacing: .margin8) {
                Text("safe_zone.src721.error.token_status_unavailable".localized)
                    .themeSubhead2(color: .themeRed)
                Spacer()
                Button("safe_zone.src721.action.retry_nfts".localized) {
                    viewModel.loadToken(tokenId: asset.token.tokenId, showError: false)
                }
                .themeSubhead2(color: .themeLeah)
            }
        }
    }

    private var operationAlertTitle: String {
        viewModel.operationState == .completed
            ? "safe_zone.src721.operation.success".localized
            : "safe_zone.src721.operation.failure".localized
    }

    private var operationAlertMessage: String {
        var messages = [viewModel.operationMessage].compactMap { $0 }.filter { !$0.isEmpty }
        if !viewModel.operationHashes.isEmpty {
            messages.append("safe_zone.src721.operation.transaction_hash".localized(viewModel.operationHashes.joined(separator: "\n")))
        }
        return messages.joined(separator: "\n\n")
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text(title.uppercased()).themeSubhead1(color: .themeLeah).padding(.top, .margin8)
            content()
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    private func detailRow(_ title: String, _ value: String, copyValue: String? = nil) -> some View {
        HStack(alignment: .top, spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            Spacer()
            if let copyValue {
                Button {
                    CopyHelper.copyAndNotify(value: copyValue)
                } label: {
                    HStack(spacing: .margin4) {
                        Text(value).themeSubhead2(color: .themeLeah, alignment: .trailing).lineLimit(1).truncationMode(.middle)
                        Image("copy_20").renderingMode(.template).foregroundColor(.themeGray)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("button.copy".localized)
            } else {
                Text(value).themeSubhead2(color: .themeLeah, alignment: .trailing).lineLimit(3).truncationMode(.middle)
            }
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            dismissSRC721Keyboard()
            action()
        }
        .buttonStyle(PrimaryButtonStyle(style: .yellow))
        .frame(height: 50)
    }
}

private struct SRC721AllowListView: View {
    @StateObject private var viewModel: SRC721AllowListViewModel
    @State private var isShowingEditor = false
    private let onUpdated: () -> Void

    init(viewModel: SRC721AllowListViewModel, onUpdated: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onUpdated = onUpdated
    }

    var body: some View {
        ThemeView {
            VStack(spacing: .margin8) {
                Text("safe_zone.src721.allow_list.hint".localized)
                    .themeSubhead2(color: .themeGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .margin16)
                    .padding(.top, .margin12)

                if !viewModel.isOwner && viewModel.dataState == .completed {
                    Text("safe_zone.src721.status.read_only".localized)
                        .themeSubhead2(color: .themeGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .margin16)
                }

                if case let .failed(message) = viewModel.dataState {
                    VStack(alignment: .leading, spacing: .margin8) {
                        Text(message)
                            .themeSubhead2(color: .themeRed)
                        Button("button.retry".localized) { viewModel.refresh() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .margin16)
                }

                if case let .unavailable(message) = viewModel.dataState {
                    Spacer()
                    PlaceholderViewNew(icon: "no_data_48", title: message)
                    Spacer()
                }

                if viewModel.dataState == .loading && viewModel.entries.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.entries.isEmpty && viewModel.dataState == .completed {
                    Spacer()
                    PlaceholderViewNew(icon: "no_data_48", title: "safe_zone.src721.empty.allow_list".localized)
                    Spacer()
                } else if !viewModel.entries.isEmpty {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            ListSection {
                                ForEach(viewModel.entries) { entry in
                                    Button {
                                        viewModel.beginEditing(entry)
                                        isShowingEditor = true
                                    } label: {
                                        SRC721AllowListRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!viewModel.isOwner || viewModel.operationState == .sending)
                                }
                            }
                            if viewModel.isLoadingNextPage {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, .margin12)
                            } else if let error = viewModel.loadMoreError {
                                VStack(spacing: .margin8) {
                                    Text(error)
                                        .themeSubhead2(color: .themeRed, alignment: .center)
                                    Button("button.retry".localized) { viewModel.loadNextPage() }
                                        .buttonStyle(SecondaryButtonStyle())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, .margin12)
                            } else if viewModel.hasMore {
                                Button("safe_zone.src721.action.load_more_allow_list".localized) {
                                    viewModel.loadNextPage()
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, .margin12)
                            }
                        }
                        .padding(.horizontal, .margin16)
                        .padding(.bottom, .margin32)
                    }
                }
            }
        }
        .navigationTitle("safe_zone.src721.allow_list.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.beginAdding()
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!viewModel.isOwner || viewModel.operationState == .sending)
                .accessibilityLabel("safe_zone.src721.action.add_allow_list".localized)
            }
        }
        .refreshable { viewModel.refresh() }
        .sheet(isPresented: $isShowingEditor) {
            SRC721AllowListEditorView(viewModel: viewModel, onUpdated: onUpdated)
        }
    }
}

private struct SRC721AllowListRow: View {
    let entry: SRC721AllowListEntry

    var body: some View {
        HStack(alignment: .top, spacing: .margin12) {
            VStack(alignment: .leading, spacing: .margin4) {
                Text(entry.address)
                    .themeSubhead1(color: .themeLeah)
                    .lineLimit(1)
//                    .truncationMode(.middle)
                Text("\("safe_zone.src721.field.allow_list_amount".localized): \(entry.amount)")
                    .themeSubhead2(color: .themeGray)
            }
            Spacer()
            Image(systemName: "pencil")
                .foregroundColor(.themeGray)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .contentShape(Rectangle())
    }
}

private struct SRC721AllowListEditorView: View {
    @ObservedObject private var viewModel: SRC721AllowListViewModel
    @Environment(\.presentationMode) private var presentationMode
    @FocusState private var focusedField: SRC721AllowListEditorField?
    private let onUpdated: () -> Void

    init(viewModel: SRC721AllowListViewModel, onUpdated: @escaping () -> Void) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onUpdated = onUpdated
    }

    private var isEditing: Bool { viewModel.editingEntry != nil }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ZStack {
                    ScrollableThemeView {
                        VStack(alignment: .leading, spacing: .margin8) {
                            Text("safe_zone.src721.allow_list.editor.hint".localized)
                                .themeSubhead2(color: .themeGray)
                            SRC721AddressInput(
                                title: "safe_zone.src721.field.allow_list_address".localized,
                                prompt: "safe_zone.src721.placeholder.allow_list_address",
                                text: $viewModel.address,
                                caution: $viewModel.addressCautionState
                            )
                            .disabled(isEditing)
                            amountInput
                        }
                        .padding(.init(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }
                    if viewModel.operationState == .sending { ProgressView() }
                }
            }
            .navigationTitle(isEditing ? "safe_zone.src721.action.edit_allow_list".localized : "safe_zone.src721.action.add_allow_list".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { presentationMode.wrappedValue.dismiss() } label: { Image("close") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("button.done".localized) { dismissKeyboard() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("safe_zone.src721.action.set_allow_list".localized) {
                    dismissKeyboard()
                    viewModel.submit()
                }
                .buttonStyle(PrimaryButtonStyle(style: .yellow))
                .disabled(viewModel.operationState == .sending || !viewModel.isOwner)
                .padding(.horizontal, .margin16)
                .padding(.vertical, .margin8)
            }
            .onChange(of: viewModel.operationState) { _, state in
                guard state == .completed else { return }
                onUpdated()
                presentationMode.wrappedValue.dismiss()
            }
            .onChange(of: viewModel.submissionID) { _, _ in
                HudHelper.instance.show(banner: .success(string: "已提交，等待区块确认"))
            }
            .alert("safe_zone.src721.error.title".localized, isPresented: Binding(
                get: { viewModel.operationMessage != nil && viewModel.operationState == .failed },
                set: { if !$0 { viewModel.operationMessage = nil } }
            )) {
                Button("button.ok".localized, role: .cancel) { viewModel.operationMessage = nil }
            } message: {
                Text(viewModel.operationMessage ?? "")
            }
        }
    }

    private var amountInput: some View {
        let limitedText = Binding<String>(
            get: { viewModel.amount },
            set: { if let value = SRC721Validation.validDecimalInput($0) { viewModel.amount = value } }
        )
        return VStack(alignment: .leading, spacing: .margin8) {
            Text("safe_zone.src721.field.allow_list_amount".localized.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(.top, .margin16)
            HStack(alignment: .top, spacing: .margin8) {
                TextField("", text: limitedText, prompt: Text("safe_zone.src721.placeholder.allow_list_amount".localized).foregroundColor(.themeGray))
                    .foregroundColor(.themeLeah)
                    .font(.themeBody)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .amount)
                if !limitedText.wrappedValue.isEmpty {
                    Button { limitedText.wrappedValue = "" } label: {
                        Image("trash_20").renderingMode(.template)
                    }
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .overlay(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous).stroke(Color.themeBlade, lineWidth: .heightOneDp))
            .modifier(CautionBorder(cautionState: $viewModel.amountCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.amountCautionState))
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        dismissSRC721Keyboard()
    }
}

struct SRC721ImportView: View {
    @StateObject private var viewModel: SRC721ImportViewModel
    @Binding private var isPresented: Bool

    init(viewModel: SRC721ImportViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                ZStack {
                    BottomGradientWrapper {
                        ScrollViewReader { proxy in
                            ScrollableThemeView {
                                VStack(spacing: .margin8) {
                                    Text("safe_zone.src721.import.hint".localized)
                                        .themeSubhead2(color: .themeGray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    SRC721AddressInput(
                                        title: "safe_zone.src721.field.contract".localized,
                                        prompt: "safe_zone.src721.placeholder.contract",
                                        text: $viewModel.address,
                                        caution: $viewModel.addressCautionState
                                    )
                                    .id(SRC721ImportField.address)
                                    VStack(spacing: .margin12) {
                                        SectionHeader(text: "safe_zone.src721.field.type".localized)
                                        Picker("", selection: $viewModel.type) {
                                            Text(SRC721ContractType.standard.title).tag(SRC721ContractType.standard)
                                            Text(SRC721ContractType.burnable.title).tag(SRC721ContractType.burnable)
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                    .padding(.horizontal, .margin16)
                                    .padding(.vertical, .margin8)
                                    .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
                                }
                                .padding(.init(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { dismissSRC721Keyboard() }
                            .onChange(of: viewModel.validationRequestID) { _, _ in
                                guard let field = viewModel.invalidField else { return }
                                DispatchQueue.main.async {
                                    withAnimation { proxy.scrollTo(field, anchor: .center) }
                                }
                            }
                        }
                    } bottomContent: {
                        Button("safe_zone.src721.action.import".localized) {
                            dismissSRC721Keyboard()
                            viewModel.importContract()
                        }
                            .disabled(viewModel.state == .sending)
                            .buttonStyle(PrimaryButtonStyle(style: .yellow))
                    }
                    if viewModel.state == .sending { ProgressView() }
                }
            }
            .navigationTitle("safe_zone.src721.import".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { isPresented = false } label: { Image("close") } }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissSRC721Keyboard() }
            .alert("safe_zone.src721.error.title".localized, isPresented: Binding(
                get: { viewModel.errorMessage != nil && viewModel.state == .failed },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("button.ok".localized, role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
            .onChange(of: viewModel.state) { _, state in
                if state == .completed {
                    HudHelper.instance.show(banner: .success(string: "safe_zone.src721.imported".localized))
                    isPresented = false
                }
            }
        }
    }

    private struct SectionHeader: View {
        let text: String
        var body: some View { Text(text.uppercased()).themeSubhead1(color: .themeLeah).padding(.top, .margin8) }
    }
}

struct SRC721ContractDetailView: View {
    @StateObject private var viewModel: SRC721ContractDetailViewModel
    @State private var baseURI = ""
    @State private var maxSupply = ""
    @State private var mintPrice = ""
    @State private var orgName = ""
    @State private var description = ""
    @State private var officialURL = ""
    @State private var whitePaperURL = ""
    @State private var recipient = ""
    @State private var approvedAddress = ""
    @State private var operatorAddress = ""
    @FocusState private var focusedField: SRC721DetailField?
    @State private var isShowingBurnConfirmation = false
    @Environment(\.presentationMode) private var presentationMode

    init(viewModel: SRC721ContractDetailViewModel) { _viewModel = StateObject(wrappedValue: viewModel) }

    var body: some View {
        ThemeView {
            detailContent
        }
        .navigationTitle(viewModel.record.name.isEmpty ? "SRC721" : viewModel.record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button.done".localized) { dismissDetailKeyboard() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissDetailKeyboard() }
        .overlay { if viewModel.isSubmittingOperation { ProgressView() } }
        .alert(operationAlertTitle, isPresented: Binding(
            get: { viewModel.operationMessage != nil && viewModel.operationState == .failed },
            set: { if !$0 { viewModel.operationMessage = nil } }
        )) {
            if !viewModel.operationHashes.isEmpty {
                Button("button.copy".localized) {
                    CopyHelper.copyAndNotify(value: viewModel.operationHashes.joined(separator: "\n"))
                    viewModel.operationMessage = nil
                }
            }
            Button("button.ok".localized, role: .cancel) { viewModel.operationMessage = nil }
        } message: { Text(operationAlertMessage) }
        .alert("safe_zone.src721.confirm.burn".localized, isPresented: $isShowingBurnConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("safe_zone.src721.action.burn".localized, role: .destructive) {
                focusedField = nil
                dismissSRC721Keyboard()
                viewModel.burn()
            }
        } message: {
            Text("safe_zone.src721.confirm.burn.details".localized)
        }
        .onAppear { syncFields() }
        .onChange(of: viewModel.contractState) { _, _ in
            syncFields()
        }
        .onChange(of: viewModel.submissionID) { _, _ in
            HudHelper.instance.show(banner: .success(string: "已提交，等待区块确认"))
            presentationMode.wrappedValue.dismiss()
        }
        .refreshable { viewModel.refresh() }
    }

    private func dismissDetailKeyboard() {
        focusedField = nil
        dismissSRC721Keyboard()
    }

    private var operationAlertTitle: String {
        viewModel.operationState == .completed
            ? "safe_zone.src721.operation.success".localized
            : "safe_zone.src721.operation.failure".localized
    }

    private var operationAlertMessage: String {
        var messages = [viewModel.operationMessage].compactMap { $0 }.filter { !$0.isEmpty }
        if !viewModel.operationHashes.isEmpty {
            messages.append("safe_zone.src721.operation.transaction_hash".localized(viewModel.operationHashes.joined(separator: "\n")))
        }
        return messages.joined(separator: "\n\n")
    }

    private var detailContent: some View {
        ScrollViewReader { proxy in
            ScrollableThemeView {
                VStack(spacing: .margin8) {
                    summary
//                    authorizationSection
                    managementSection
                    logoSection
//                    withdrawSection
//                    tokenSection
                }
                .padding(.init(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissDetailKeyboard() }
            .onChange(of: viewModel.validationRequestID) { _, _ in
                guard let field = viewModel.invalidField else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(field, anchor: .center) }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            detailRow("safe_zone.src721.field.contract".localized, viewModel.record.contractAddress, copyValue: viewModel.record.contractAddress)
            detailRow("safe_zone.src721.field.type".localized, viewModel.record.contractType.title)
            if let state = viewModel.contractState {
                detailRow("safe_zone.src721.field.owner".localized, state.ownerAddress, copyValue: state.ownerAddress)
                detailRow("safe_zone.src721.field.supply".localized, "\(state.totalSupply) / \(state.maxSupply)")
                detailRow("safe_zone.src721.field.burned_count".localized, state.burnedCount?.description ?? "-")
                detailRow("safe_zone.src721.field.remain".localized, state.remainSupply.description)
                Text(viewModel.canManage ? "safe_zone.src721.status.manager".localized : "safe_zone.src721.status.read_only".localized)
                    .themeSubhead2(color: viewModel.canManage ? .themeGreen : .themeGray)
            } else {
                contractStateStatus
            }
            if let refreshErrorMessage = viewModel.refreshErrorMessage {
                HStack(alignment: .top, spacing: .margin8) {
                    Text(refreshErrorMessage)
                        .themeSubhead2(color: .themeRed)
                    Spacer()
                    Button("button.retry".localized) { viewModel.refresh() }
                        .themeSubhead2(color: .themeLeah)
                        .disabled(viewModel.isRefreshing)
                }
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    @ViewBuilder private var contractStateStatus: some View {
        switch viewModel.dataState {
        case .loading:
            HStack(spacing: .margin8) {
                ProgressView()
                Text("safe_zone.src721.error.contract_state_unavailable".localized)
                    .themeSubhead2(color: .themeGray)
            }
        case let .failed(message), let .unavailable(message):
            HStack(alignment: .top, spacing: .margin8) {
                Text(message)
                    .themeSubhead2(color: .themeRed)
                Spacer()
                Button("button.retry".localized) { viewModel.refresh() }
                    .themeSubhead2(color: .themeLeah)
                    .disabled(viewModel.isRefreshing)
            }
        case .completed:
            EmptyView()
        }
    }

    private var authorizationSection: some View {
        section(title: "safe_zone.src721.section.authorization".localized) {
            Text("safe_zone.src721.authorization.hint".localized)
                .themeSubhead2(color: .themeGray)
            SRC721AddressInput(
                title: "safe_zone.src721.field.operator".localized,
                prompt: "safe_zone.src721.placeholder.operator",
                text: $operatorAddress,
                caution: $viewModel.operatorCautionState
            )
            HStack(spacing: .margin8) {
                actionButton("safe_zone.src721.action.approve_all".localized) {
                    viewModel.setApprovalForAll(operatorAddress: operatorAddress, approved: true)
                }
                .disabled(!viewModel.canTransact)
                actionButton("safe_zone.src721.action.revoke_all".localized) {
                    viewModel.setApprovalForAll(operatorAddress: operatorAddress, approved: false)
                }
                .disabled(!viewModel.canTransact)
            }
        }
    }

    private var managementSection: some View {
        section(title: "safe_zone.src721.section.management".localized) {
            managementInput(title: "safe_zone.src721.field.base_uri".localized, prompt: "safe_zone.src721.placeholder.base_uri", text: $baseURI, field: .baseURI, caution: $viewModel.baseURICautionState, keyboard: .URL) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.baseURIMaxUTF8Length) }.id(SRC721DetailField.baseURI)
            managementInput(title: "safe_zone.src721.field.max_supply".localized, prompt: "safe_zone.src721.placeholder.max_supply", text: $maxSupply, field: .maxSupply, caution: $viewModel.maxSupplyCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }.id(SRC721DetailField.maxSupply)
            managementInput(title: "safe_zone.src721.field.mint_price".localized, prompt: "safe_zone.src721.placeholder.mint_price", text: $mintPrice, field: .mintPrice, caution: $viewModel.mintPriceCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }.id(SRC721DetailField.mintPrice)
//            NavigationLink {
//                if let allowListViewModel = SRC721Module.allowListViewModel(record: viewModel.record) {
//                    SRC721AllowListView(viewModel: allowListViewModel) {
//                        viewModel.refresh()
//                    }
//                }
//            } label: {
//                HStack {
//                    Text("safe_zone.src721.action.manage_allow_list".localized)
//                        .themeSubhead1(color: .themeLeah)
//                    Spacer()
//                    Image(systemName: "chevron.right")
//                        .foregroundColor(.themeGray)
//                }
//                .padding(.vertical, .margin12)
//            }
//            .disabled(!viewModel.canManage)
            managementInput(title: "safe_zone.src721.field.org_name".localized, prompt: "safe_zone.src721.placeholder.org_name", text: $orgName, field: .orgName, caution: $viewModel.orgNameCautionState)
            managementInput(title: "safe_zone.src721.field.description".localized, prompt: "safe_zone.src721.placeholder.description", text: $description, field: .description, caution: $viewModel.descriptionCautionState, axis: .vertical, minHeight: 96)
            managementInput(title: "safe_zone.src721.field.official_url".localized, prompt: "safe_zone.src721.placeholder.official_url", text: $officialURL, field: .officialURL, caution: $viewModel.officialURLCautionState, keyboard: .URL)
            managementInput(title: "safe_zone.src721.field.whitepaper_url".localized, prompt: "safe_zone.src721.placeholder.whitepaper_url", text: $whitePaperURL, field: .whitePaperURL, caution: $viewModel.whitePaperURLCautionState, keyboard: .URL)
            actionButton("safe_zone.src721.action.update_all".localized) {
                viewModel.updateAll(
                    baseURI: baseURI,
                    maxSupply: maxSupply,
                    mintPrice: mintPrice,
                    orgName: orgName,
                    description: description,
                    officialURL: officialURL,
                    whitePaperURL: whitePaperURL,
                    logo: nil
                )
            }
            .disabled(!viewModel.canManage || viewModel.operationState == .sending || !viewModel.hasUpdateChanges(baseURI: baseURI, maxSupply: maxSupply, mintPrice: mintPrice, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: nil))
        }
        .disabled(!viewModel.isContractStateReady)
        .opacity(viewModel.isContractStateReady ? 1 : 0.65)
    }

    private var logoSection: some View {
        section(title: "safe_zone.src721.section.logo".localized) {
            NavigationLink {
                if let state = viewModel.contractState,
                   let logoViewModel = SRC721Module.logoViewModel(record: viewModel.record, currentLogo: state.logo) {
                    SRC721LogoView(viewModel: logoViewModel) { viewModel.refresh() }
                } else {
                    Text("safe_zone.src721.error.signer".localized)
                }
            } label: {
                HStack(spacing: .margin12) {
                    logoPreview(data: viewModel.contractState?.logo)
                    Text("safe_zone.src721.action.set_logo".localized)
                        .themeSubhead1(color: viewModel.canManage ? .themeLeah : .themeGray)
                    Spacer(minLength: .margin8)
                    Image(systemName: "chevron.right").foregroundColor(.themeGray)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canManage || !viewModel.isContractStateReady)
        }
    }

    @ViewBuilder private func logoPreview(data: Data?) -> some View {
        Group {
            if let data, !data.isEmpty, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .padding(.margin12)
                    .foregroundColor(.themeGray)
            }
        }
        .frame(width: 56, height: 56)
        .background(Color.themeBlade)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous))
    }

    private var tokenSection: some View {
        section(title: "safe_zone.src721.section.token".localized) {
            input("safe_zone.src721.field.token_id".localized, prompt: "", text: $viewModel.tokenId, caution: $viewModel.tokenIdCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }
                .id(SRC721DetailField.tokenId)
            actionButton("safe_zone.src721.action.query_token".localized) { viewModel.loadToken() }
            if let token = viewModel.tokenState {
                detailRow("safe_zone.src721.field.owner".localized, token.ownerAddress, copyValue: token.ownerAddress)
//                detailRow("safe_zone.src721.field.approved".localized, token.approvedAddress)
//                detailRow("safe_zone.src721.field.operator_status".localized, token.isApprovedForAll ? "safe_zone.src721.status.authorized".localized : "safe_zone.src721.status.not_authorized".localized)
                detailRow("safe_zone.src721.field.token_uri".localized, token.tokenURI ?? "safe_zone.src721.metadata.unavailable".localized)
                Text(viewModel.canTransferLoadedToken ? "safe_zone.src721.status.token_operable".localized : "safe_zone.src721.status.token_read_only".localized)
                    .themeSubhead2(color: viewModel.canTransferLoadedToken ? .themeGreen : .themeGray)
            }
            SRC721AddressInput(title: "safe_zone.src721.field.recipient".localized, prompt: "safe_zone.src721.placeholder.recipient", text: $recipient, caution: $viewModel.tokenRecipientCautionState)
                .id(SRC721DetailField.tokenRecipient)
            HStack(spacing: .margin8) {
                actionButton("safe_zone.src721.action.approve".localized) {
                    let address = approvedAddress.isEmpty ? recipient : approvedAddress
                    guard viewModel.validateTokenOperation(recipient: address, allowZeroRecipient: true) else { return }
                    viewModel.approve(to: address)
                }
                    .disabled(!viewModel.canTransact || !viewModel.canApproveLoadedToken || viewModel.tokenOperationPending)
                actionButton("safe_zone.src721.action.transfer".localized) {
                    guard viewModel.validateTokenOperation(recipient: recipient, allowZeroRecipient: false) else { return }
                    viewModel.transfer(to: recipient)
                }
                    .disabled(!viewModel.canTransact || !viewModel.canTransferLoadedToken || viewModel.tokenOperationPending)
                actionButton("safe_zone.src721.action.burn".localized) {
                    guard viewModel.validateTokenIdInput() else { return }
                    isShowingBurnConfirmation = true
                }
                    .disabled(!viewModel.canTransact || !viewModel.canBurnLoadedToken || viewModel.tokenOperationPending)
            }
        }
    }

    private func syncFields() {
        guard let state = viewModel.contractState else { return }
        baseURI = state.baseURI
        maxSupply = state.maxSupply.description
        mintPrice = state.mintPrice.description
        orgName = state.orgName
        description = state.description
        officialURL = state.officialURL
        whitePaperURL = state.whitePaperURL
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text(title.uppercased()).themeSubhead1(color: .themeLeah).padding(.top, .margin8)
            content()
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    private func input(_ title: String, prompt: String, text: Binding<String>, caution: Binding<CautionState> = .constant(.none), keyboard: UIKeyboardType = .default, axis: Axis = .horizontal, transform: @escaping (String) -> String? = { Optional($0) }) -> some View {
        let limitedText = Binding<String>(
            get: { text.wrappedValue },
            set: { if let value = transform($0) { text.wrappedValue = value } }
        )

        return VStack(alignment: .leading, spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            TextField("", text: limitedText, prompt: Text(prompt.localized).foregroundColor(.themeGray), axis: axis)
                .foregroundColor(.themeLeah)
                .font(.themeBody)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, .margin12)
                .padding(.vertical, .margin8)
                .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
                .overlay(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous).stroke(Color.themeBlade, lineWidth: .heightOneDp))
                .modifier(CautionBorder(cautionState: caution))
                .modifier(CautionPrompt(cautionState: caution))
        }
    }

    private func managementInput(title: String, prompt: String, text: Binding<String>, field: SRC721DetailField, caution: Binding<CautionState>, keyboard: UIKeyboardType = .default, axis: Axis = .vertical, minHeight: CGFloat = 0, transform: @escaping (String) -> String? = { $0 }) -> some View {
        let limitedText = Binding<String>(
            get: { text.wrappedValue },
            set: { if let value = transform($0) { text.wrappedValue = value } }
        )

        return VStack(alignment: .leading, spacing: .margin8) {
            Text(title.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(.top, .margin16)
            HStack(alignment: .top, spacing: .margin8) {
                TextField("", text: limitedText, prompt: Text(prompt.localized).foregroundColor(.themeGray), axis: axis)
                    .lineLimit(1...)
                    .frame(minHeight: minHeight, alignment: .top)
                    .foregroundColor(.themeLeah)
                    .font(.themeBody)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                if !limitedText.wrappedValue.isEmpty {
                    Button { limitedText.wrappedValue = "" } label: { Image("trash_20").renderingMode(.template) }
                        .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .overlay(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous).stroke(Color.themeBlade, lineWidth: .heightOneDp))
            .modifier(CautionBorder(cautionState: caution))
            .modifier(CautionPrompt(cautionState: caution))
        }
    }

    private func detailRow(_ title: String, _ value: String, copyValue: String? = nil) -> some View {
        HStack(alignment: .top, spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            Spacer()
            if let copyValue {
                Button {
                    CopyHelper.copyAndNotify(value: copyValue)
                } label: {
                    HStack(spacing: .margin4) {
                        Text(value).themeSubhead2(color: .themeLeah, alignment: .trailing).lineLimit(1).truncationMode(.middle)
                        Image("copy_20").renderingMode(.template).foregroundColor(.themeGray)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("button.copy".localized)
            } else {
                Text(value).themeSubhead2(color: .themeLeah, alignment: .trailing).lineLimit(3).truncationMode(.middle)
            }
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            focusedField = nil
            dismissSRC721Keyboard()
            action()
        }
            .buttonStyle(PrimaryButtonStyle(style: .yellow))
            .frame(height: 50)
    }
}

private func dismissSRC721Keyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct SRC721AddressInput: View {
    let title: String
    let prompt: String
    @Binding var text: String
    @Binding var caution: CautionState
    let multiline: Bool
    let showsShortcuts: Bool
    let transform: (String) -> String?
    @FocusState private var isFocused: Bool

    init(title: String, prompt: String, text: Binding<String>, caution: Binding<CautionState>, multiline: Bool = false, showsShortcuts: Bool = true, transform: @escaping (String) -> String? = { Optional($0) }) {
        self.title = title
        self.prompt = prompt
        _text = text
        _caution = caution
        self.multiline = multiline
        self.showsShortcuts = showsShortcuts
        self.transform = transform
    }

    var body: some View {
        let limitedText = Binding<String>(
            get: { text },
            set: { if let value = transform($0) { text = value } }
        )

        return VStack(alignment: .leading, spacing: .margin8) {
            Text(title.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(.top, .margin16)
            HStack(alignment: .top, spacing: .margin8) {
                TextField("", text: limitedText, prompt: Text(prompt.localized).foregroundColor(.themeGray), axis: multiline ? .vertical : .horizontal)
                    .lineLimit(1...)
                    .frame(minHeight: multiline ? 72 : 0, alignment: .top)
                    .foregroundColor(.themeLeah)
                    .font(.themeBody)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                if showsShortcuts {
                    ShortcutButtonsView(
                        showDelete: .init(get: { !limitedText.wrappedValue.isEmpty }, set: { _ in }),
                        items: [.icon("scan"), .text("button.paste".localized)],
                        onTap: handleShortcut,
                        onTapDelete: { limitedText.wrappedValue = "" }
                    )
                } else if !limitedText.wrappedValue.isEmpty {
                    Button { limitedText.wrappedValue = "" } label: {
                        Image("trash_20").renderingMode(.template)
                    }
                    .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                }
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .overlay(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous).stroke(Color.themeBlade, lineWidth: .heightOneDp))
            .modifier(CautionBorder(cautionState: $caution))
            .modifier(CautionPrompt(cautionState: $caution))
        }
    }

    private func handleShortcut(_ index: Int) {
        switch index {
        case 0:
            Coordinator.shared.present { isPresented in
                ScanQrViewNew(options: [], isPresented: isPresented) { value in
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let value = transform(normalized) { text = value }
                }
                .ignoresSafeArea()
            }
        default:
            guard let value = UIPasteboard.general.string else { return }
            let normalized = multiline
                ? value.trimmingCharacters(in: .whitespacesAndNewlines)
                : value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = transform(normalized) { text = value }
        }
    }
}
