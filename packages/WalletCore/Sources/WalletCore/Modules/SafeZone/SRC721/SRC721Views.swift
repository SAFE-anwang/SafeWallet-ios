import SwiftUI
import PhotosUI
import UIKit

private struct SRC721MintConfirmation: Identifiable {
    let id = UUID()
    let recipient: String
    let amount: String
    let isAdmin: Bool
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
                        ScrollableThemeView {
                            VStack(spacing: .margin8) {
                                typeView
                                hintView
                                input(title: "safe_zone.src721.field.name".localized, text: $viewModel.name, prompt: "safe_zone.src721.placeholder.name", field: .name, caution: $viewModel.nameCautionState, keyboard: .default) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.nameMaxUTF8Length) }
                                input(title: "safe_zone.src721.field.symbol".localized, text: $viewModel.symbol, prompt: "safe_zone.src721.placeholder.symbol", field: .symbol, caution: $viewModel.symbolCautionState, keyboard: .default) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.symbolMaxUTF8Length) }
                                input(title: "safe_zone.src721.field.base_uri".localized, text: $viewModel.baseURI, prompt: "safe_zone.src721.placeholder.base_uri", field: .baseURI, caution: $viewModel.baseURICautionState, keyboard: .URL) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.baseURIMaxUTF8Length) }
                                input(title: "safe_zone.src721.field.max_supply".localized, text: $viewModel.maxSupply, prompt: "safe_zone.src721.placeholder.max_supply", field: .maxSupply, caution: $viewModel.maxSupplyCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }
                                input(title: "safe_zone.src721.field.mint_price".localized, text: $viewModel.mintPrice, prompt: "safe_zone.src721.placeholder.mint_price", field: .mintPrice, caution: $viewModel.mintPriceCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }
                            }
                            .padding(.init(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                        }
                    } bottomContent: {
                        Button("safe_zone.src721.action.deploy".localized) {
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
                    Button("button.done".localized) { focusedField = nil }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
            .alert("safe_zone.src721.confirm.deploy".localized, isPresented: $isShowingConfirmation) {
                Button("button.cancel".localized, role: .cancel) {}
                Button("button.confirm".localized) { viewModel.deploy() }
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
                    HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                    isPresented = false
                }
            }
        }
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
        Text("safe_zone.src721.deploy.hint".localized)
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

private enum SRC721DeployField: Hashable {
    case name, symbol, baseURI, maxSupply, mintPrice
}

struct SRC721ManagerView: View {
    @StateObject private var viewModel: SRC721ManagerViewModel
    @Binding private var isPresented: Bool
    @State private var isShowingImport = false

    init(viewModel: SRC721ManagerViewModel, isPresented: Binding<Bool>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isPresented = isPresented
    }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                VStack(spacing: .margin8) {
                    Text("safe_zone.src721.manager.hint".localized)
                        .themeSubhead2(color: .themeGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .margin16)
                        .padding(.top, .margin12)
                    if viewModel.records.isEmpty {
                        Spacer()
                        PlaceholderViewNew(icon: "no_data_48", title: "safe_zone.src721.empty".localized)
                        Spacer()
                    } else {
                        ScrollableThemeView {
                            ListSection {
                                ForEach(viewModel.records) { record in
                                    NavigationLink { SRC721ContractDetailRoute(record: record) } label: {
                                        recordRow(record)
                                    }
                                }
                            }
                            .padding(.horizontal, .margin16)
                            .padding(.bottom, .margin32)
                        }
                    }
                }
            }
            .navigationTitle("safe_zone.src721.manager".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { isPresented = false } label: { Image("close") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isShowingImport = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("safe_zone.src721.action.import".localized)
                }
            }
            .refreshable { viewModel.refresh() }
            .sheet(isPresented: $isShowingImport) {
                if let importViewModel = SRC721Module.importViewModel() {
                    SRC721ImportView(viewModel: importViewModel, isPresented: $isShowingImport)
                }
            }
        }
    }

    private func recordRow(_ record: SRC721ContractRecord) -> some View {
        VStack(alignment: .leading, spacing: .margin8) {
            HStack {
                Text("\("safe_zone.src721.field.name".localized): \(record.name.isEmpty ? "SRC721" : record.name)")
                .themeSubhead1(color: .themeLeah)
                Spacer()
                Text(record.contractType.title).themeMicro(color: .themeGray, alignment: .trailing)
            }
            Text("\("safe_zone.src721.field.symbol".localized): \(record.symbol)")
                .themeSubhead2(color: .themeGray)
            Text("\("safe_zone.src721.field.contract".localized): \(record.contractAddress)")
                .themeMicro(color: .blue)
                .truncationMode(.middle)
                .lineLimit(1)
            if record.isPending {
                Text("safe_zone.src721.status.pending".localized).themeMicro(color: .themeAndy)
            } else if record.isReadOnly {
                Text("safe_zone.src721.status.read_only".localized).themeMicro(color: .themeGray)
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
    }
}

private struct SRC721ContractDetailRoute: View {
    let record: SRC721ContractRecord
    @State private var viewModel: SRC721ContractDetailViewModel?

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
            viewModel = SRC721Module.detailViewModel(record: record)
        }
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
                        ScrollableThemeView {
                            VStack(spacing: .margin8) {
                                Text("safe_zone.src721.import.hint".localized)
                                    .themeSubhead2(color: .themeGray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    SRC721AddressInput(
                                        title: "safe_zone.src721.field.contract".localized,
                                        prompt: "safe_zone.src721.placeholder.contract",
                                        text: $viewModel.address,
                                        caution: .constant(.none)
                                    )
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
                    } bottomContent: {
                        Button("safe_zone.src721.action.import".localized) { viewModel.importContract() }
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
    @State private var recipient = ""
    @State private var amount = "1"
    @State private var baseURI = ""
    @State private var maxSupply = ""
    @State private var mintPrice = ""
    @State private var allowListAddresses = ""
    @State private var allowListAmounts = ""
    @State private var orgName = ""
    @State private var description = ""
    @State private var officialURL = ""
    @State private var whitePaperURL = ""
    @State private var approvedAddress = ""
    @State private var selectedLogo: PhotosPickerItem?
    @State private var pendingLogoData: Data?
    @FocusState private var focusedField: SRC721DetailField?
    @State private var mintConfirmation: SRC721MintConfirmation?
    @State private var isShowingBurnConfirmation = false
    @State private var isShowingWithdrawConfirmation = false

    init(viewModel: SRC721ContractDetailViewModel) { _viewModel = StateObject(wrappedValue: viewModel) }

    var body: some View {
        ThemeView {
            switch viewModel.dataState {
            case .loading: ProgressView()
            case let .failed(message): PlaceholderViewNew(icon: "no_data_48", title: message)
            case .completed:
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        summary
                        mintSection
                        managementSection
                        withdrawSection
                        tokenSection
                    }
                    .padding(.init(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
                }
            }
        }
        .navigationTitle(viewModel.record.name.isEmpty ? "SRC721" : viewModel.record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button.done".localized) { focusedField = nil }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .overlay { if viewModel.operationState == .sending { ProgressView() } }
        .alert("safe_zone.src721.operation.result".localized, isPresented: Binding(
            get: { viewModel.operationMessage != nil && viewModel.operationState != .sending },
            set: { if !$0 { viewModel.operationMessage = nil } }
        )) {
            Button("button.ok".localized, role: .cancel) { viewModel.operationMessage = nil }
        } message: { Text(viewModel.operationMessage ?? "") }
        .alert(item: $mintConfirmation) { confirmation in
            Alert(
                title: Text("safe_zone.src721.confirm.mint".localized),
                message: Text(confirmation.isAdmin ? "safe_zone.src721.confirm.admin_mint".localized : "safe_zone.src721.confirm.mint.details".localized(confirmation.amount, confirmation.recipient)),
                primaryButton: .destructive(Text("button.confirm".localized)) {
                    viewModel.mint(to: confirmation.recipient, amount: confirmation.amount, admin: confirmation.isAdmin)
                },
                secondaryButton: .cancel(Text("button.cancel".localized))
            )
        }
        .alert("safe_zone.src721.confirm.burn".localized, isPresented: $isShowingBurnConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("safe_zone.src721.action.burn".localized, role: .destructive) { viewModel.burn() }
        } message: {
            Text("safe_zone.src721.confirm.burn.details".localized)
        }
        .alert("safe_zone.src721.confirm.withdraw".localized, isPresented: $isShowingWithdrawConfirmation) {
            Button("button.cancel".localized, role: .cancel) {}
            Button("safe_zone.src721.action.withdraw".localized, role: .destructive) { viewModel.withdraw() }
        } message: {
            Text("safe_zone.src721.confirm.withdraw.details".localized(viewModel.contractState?.safeBalance.safe4Amount() ?? "0"))
        }
        .onAppear { syncFields() }
        .onChange(of: viewModel.contractState) { _, _ in
            syncFields()
        }
        .onChange(of: viewModel.operationState) { _, state in
            if state == .completed {
                pendingLogoData = nil
                selectedLogo = nil
            }
        }
        .onChange(of: selectedLogo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { pendingLogoData = data }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: .margin8) {
            detailRow("safe_zone.src721.field.contract".localized, viewModel.record.contractAddress)
            detailRow("safe_zone.src721.field.type".localized, viewModel.record.contractType.title)
            if let state = viewModel.contractState {
                detailRow("safe_zone.src721.field.owner".localized, state.ownerAddress)
                detailRow("safe_zone.src721.field.supply".localized, "\(state.totalSupply) / \(state.maxSupply)")
                detailRow("safe_zone.src721.field.remain".localized, state.remainSupply.description)
                detailRow("safe_zone.src721.field.wallet_balance".localized, state.walletBalance.description)
                Text(viewModel.canManage ? "safe_zone.src721.status.manager".localized : "safe_zone.src721.status.read_only".localized)
                    .themeSubhead2(color: viewModel.canManage ? .themeGreen : .themeGray)
            }
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin12)
        .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
    }

    private var mintSection: some View {
        section(title: "safe_zone.src721.section.mint".localized) {
            SRC721AddressInput(title: "safe_zone.src721.field.recipient".localized, prompt: "safe_zone.src721.placeholder.recipient", text: $recipient, caution: .constant(.none))
            input("safe_zone.src721.field.amount".localized, text: $amount, keyboard: .numberPad)
            HStack(spacing: .margin8) {
                actionButton("safe_zone.src721.action.mint".localized) { mintConfirmation = SRC721MintConfirmation(recipient: recipient, amount: amount, isAdmin: false) }
                    .disabled(!viewModel.canTransact)
                actionButton("safe_zone.src721.action.admin_mint".localized) { mintConfirmation = SRC721MintConfirmation(recipient: recipient, amount: amount, isAdmin: true) }
                    .disabled(!viewModel.canManage)
            }
        }
    }

    private var managementSection: some View {
        section(title: "safe_zone.src721.section.management".localized) {
            managementInput(title: "safe_zone.src721.field.base_uri".localized, prompt: "safe_zone.src721.placeholder.base_uri", text: $baseURI, field: .baseURI, caution: $viewModel.baseURICautionState, keyboard: .URL) { SRC721Validation.textInput($0, maxUTF8Length: SRC721Validation.baseURIMaxUTF8Length) }
            managementInput(title: "safe_zone.src721.field.max_supply".localized, prompt: "safe_zone.src721.placeholder.max_supply", text: $maxSupply, field: .maxSupply, caution: $viewModel.maxSupplyCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }
            managementInput(title: "safe_zone.src721.field.mint_price".localized, prompt: "safe_zone.src721.placeholder.mint_price", text: $mintPrice, field: .mintPrice, caution: $viewModel.mintPriceCautionState, keyboard: .numberPad) { SRC721Validation.validDecimalInput($0) }
            allowListStatus
            SRC721AddressInput(title: "safe_zone.src721.field.allow_list_addresses".localized, prompt: "safe_zone.src721.placeholder.allow_list_addresses", text: $allowListAddresses, caution: $viewModel.allowListCautionState, multiline: true, showsShortcuts: false) { SRC721Validation.allowListAddressesInput($0) }
            managementInput(title: "safe_zone.src721.field.allow_list_amounts".localized, prompt: "safe_zone.src721.placeholder.allow_list_amounts", text: $allowListAmounts, field: .allowListAmounts, caution: $viewModel.allowListCautionState, keyboard: .numbersAndPunctuation, axis: .vertical) { SRC721Validation.allowListAmountsInput($0) }
            managementInput(title: "safe_zone.src721.field.org_name".localized, prompt: "safe_zone.src721.placeholder.org_name", text: $orgName, field: .orgName, caution: $viewModel.orgNameCautionState)
            managementInput(title: "safe_zone.src721.field.description".localized, prompt: "safe_zone.src721.placeholder.description", text: $description, field: .description, caution: $viewModel.descriptionCautionState, axis: .vertical, minHeight: 96)
            managementInput(title: "safe_zone.src721.field.official_url".localized, prompt: "safe_zone.src721.placeholder.official_url", text: $officialURL, field: .officialURL, caution: $viewModel.officialURLCautionState, keyboard: .URL)
            managementInput(title: "safe_zone.src721.field.whitepaper_url".localized, prompt: "safe_zone.src721.placeholder.whitepaper_url", text: $whitePaperURL, field: .whitePaperURL, caution: $viewModel.whitePaperURLCautionState, keyboard: .URL)
            PhotosPicker(selection: $selectedLogo, matching: .images) {
                HStack(spacing: .margin12) {
                    logoPreview
                    Text(pendingLogoData == nil ? "safe_zone.src721.action.choose_logo".localized : "safe_zone.src721.action.logo_selected".localized)
                        .themeSubhead1(color: .themeLeah)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: .margin8)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.themeGray)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canManage)
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: $viewModel.logoCautionState))
            .modifier(CautionPrompt(cautionState: $viewModel.logoCautionState))
            actionButton("safe_zone.src721.action.update_all".localized) {
                viewModel.updateAll(
                    baseURI: baseURI,
                    maxSupply: maxSupply,
                    mintPrice: mintPrice,
                    allowListAddresses: allowListAddresses,
                    allowListAmounts: allowListAmounts,
                    orgName: orgName,
                    description: description,
                    officialURL: officialURL,
                    whitePaperURL: whitePaperURL,
                    logo: pendingLogoData
                )
            }
            .disabled(!viewModel.canManage || viewModel.operationState == .sending || !viewModel.hasUpdateChanges(baseURI: baseURI, maxSupply: maxSupply, mintPrice: mintPrice, allowListAddresses: allowListAddresses, allowListAmounts: allowListAmounts, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: pendingLogoData))
        }
    }

    private var withdrawSection: some View {
        section(title: "safe_zone.src721.section.withdraw".localized) {
            detailRow("safe_zone.src721.field.withdrawable_safe".localized, viewModel.contractState?.safeBalance.safe4Amount() ?? "-")
            actionButton("safe_zone.src721.action.withdraw".localized) { isShowingWithdrawConfirmation = true }
                .disabled(!viewModel.canManage || viewModel.operationState == .sending || (viewModel.contractState?.safeBalance ?? 0) == 0)
        }
    }

    private var allowListStatus: some View {
        let addressCount = allowListEntryCount(allowListAddresses)
        let amountCount = allowListEntryCount(allowListAmounts)
        let hasInput = addressCount > 0 || amountCount > 0
        let isMatched = hasInput && addressCount == amountCount && addressCount > 0
        let message: String
        if !hasInput {
            message = "safe_zone.src721.allow_list.status.empty".localized
        } else if isMatched {
            message = "safe_zone.src721.allow_list.status.match".localized(addressCount, amountCount)
        } else {
            message = "safe_zone.src721.allow_list.status.mismatch".localized(addressCount, amountCount)
        }
        let statusColor = isMatched ? Color.themeGreen : (hasInput ? Color.themeRed : Color.themeGray)
        let statusIcon = isMatched ? "checkmark.circle.fill" : (hasInput ? "exclamationmark.circle" : "info.circle")

        return HStack(alignment: .top, spacing: .margin8) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            Text(message)
                .themeSubhead2(color: statusColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, .margin16)
        .padding(.vertical, .margin8)
    }

    private func allowListEntryCount(_ value: String) -> Int {
        value.split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }.count
    }

    private var logoPreview: some View {
        Group {
            if let pendingLogoData, let image = UIImage(data: pendingLogoData) {
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
            input("safe_zone.src721.field.token_id".localized, text: $viewModel.tokenId, keyboard: .numberPad)
            actionButton("safe_zone.src721.action.query_token".localized) { viewModel.loadToken() }
            if let token = viewModel.tokenState {
                detailRow("safe_zone.src721.field.owner".localized, token.ownerAddress)
                detailRow("safe_zone.src721.field.approved".localized, token.approvedAddress)
                detailRow("safe_zone.src721.field.token_uri".localized, token.tokenURI)
            }
            SRC721AddressInput(title: "safe_zone.src721.field.recipient".localized, prompt: "safe_zone.src721.placeholder.recipient", text: $recipient, caution: .constant(.none))
            HStack(spacing: .margin8) {
                actionButton("safe_zone.src721.action.approve".localized) { viewModel.approve(to: approvedAddress.isEmpty ? recipient : approvedAddress) }
                    .disabled(!viewModel.canTransact)
                actionButton("safe_zone.src721.action.transfer".localized) { viewModel.transfer(to: recipient) }
                    .disabled(!viewModel.canTransact)
                actionButton("safe_zone.src721.action.burn".localized) { isShowingBurnConfirmation = true }
                    .disabled(!viewModel.record.contractType.canBurn || !viewModel.canTransact)
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

    private func input(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            TextField("", text: text, axis: axis)
                .foregroundColor(.themeLeah)
                .font(.themeHeadline1)
                .keyboardType(keyboard)
                .padding(.horizontal, .margin12)
                .padding(.vertical, .margin8)
                .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
                .overlay(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous).stroke(Color.themeBlade, lineWidth: .heightOneDp))
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

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: .margin8) {
            Text(title).themeSubhead2(color: .themeGray)
            Spacer()
            Text(value).themeSubhead2(color: .themeLeah, alignment: .trailing).lineLimit(3).truncationMode(.middle)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle(style: .yellow))
            .frame(height: 50)
    }
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

private enum SRC721DetailField: Hashable {
    case baseURI, maxSupply, mintPrice, allowListAddresses, allowListAmounts, orgName, description, officialURL, whitePaperURL
}
