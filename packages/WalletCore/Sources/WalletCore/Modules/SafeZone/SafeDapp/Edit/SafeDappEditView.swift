import SwiftUI
import UIKit

struct SafeDappEditView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SafeDappEditViewModel
    @State private var logoViewModel: SafeDappLogoViewModel?
    @FocusState private var focusedField: SafeDappField?
    @State private var showConfirm = false

    init(viewModel: SafeDappEditViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _logoViewModel = State(initialValue: SafeDappModule.logoViewModel(info: viewModel.info, currentLogo: viewModel.currentLogo))
    }

    var body: some View {
        ThemeView {
            ZStack {
                BottomGradientWrapper {
                    ScrollableThemeView {
                        VStack(spacing: .margin8) {
                            ForEach(SafeDappField.editableFields) { field in
                                input(title: field.title, text: binding(for: field), field: field, caution: cautionBinding(for: field), keyboardType: keyboardType(for: field))
                            }
                            logoSetting
                        }
                        .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                    }
                } bottomContent: {
                    Button(action: {
                        if viewModel.validateForSubmit() {
                            showConfirm = true
                        }
                    }) {
                        Text("safe_dapp.update".localized)
                    }
                    .buttonStyle(PrimaryButtonStyle(style: .yellow))
                    .disabled(viewModel.sendState == .sending || !viewModel.hasChanges)
                }

                if viewModel.sendState == .sending {
                    ProgressView()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("button.done".localized) { focusedField = nil }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .navigationBarTitle("safe_dapp.edit".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("safe_dapp.update_confirm".localized, isPresented: $showConfirm, actions: {
            Button("button.cancel".localized, role: .cancel) {}
            Button("button.confirm".localized) {
                viewModel.update { state in
                    switch state {
                    case .completed:
                        HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                        presentationMode.wrappedValue.dismiss()
                    case let .failed(message):
                        HudHelper.instance.show(banner: .error(string: message))
                    default: ()
                    }
                }
            }
        })
    }

    private func binding(for field: SafeDappField) -> Binding<String> {
        let box = viewModel.binding(for: field)
        return Binding(get: box.get, set: box.set)
    }

    private func cautionBinding(for field: SafeDappField) -> Binding<CautionState> {
        let box = viewModel.cautionBinding(for: field)
        return Binding(get: box.get, set: box.set)
    }

    private func keyboardType(for field: SafeDappField) -> UIKeyboardType {
        switch field {
        case .runUrl, .gitUrl, .officialUrl: return .URL
        case .officialEmail: return .emailAddress
        default: return .default
        }
    }

    @ViewBuilder
    private func input(title: String, text: Binding<String>, field: SafeDappField, caution: Binding<CautionState>, keyboardType: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text(title.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))

            HStack(alignment: .top, spacing: .margin8) {
                TextField("", text: text, prompt: Text(field.prompt.localized).foregroundColor(.themeGray), axis: .vertical)
                    .lineLimit(1...)
                    .foregroundColor(.themeLeah)
                    .font(.themeBody)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                    .frame(minHeight: field == .description ? 96 : 0, alignment: .top)

                if field == .contractAddr {
                    ShortcutButtonsView(
                        showDelete: .init(get: { !text.wrappedValue.isEmpty }, set: { _ in }),
                        items: [.icon("scan"), .text("button.paste".localized)],
                        onTap: { index in
                            switch index {
                            case 0:
                                Coordinator.shared.present { isPresented in
                                    ScanQrViewNew(options: [], isPresented: isPresented) { value in
                                        text.wrappedValue = value
                                    }
                                    .ignoresSafeArea()
                                }
                            default:
                                if let value = UIPasteboard.general.string?.replacingOccurrences(of: "\n", with: " ") {
                                    text.wrappedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                        },
                        onTapDelete: { text.wrappedValue = "" }
                    )
                }

                if !text.wrappedValue.isEmpty && field != .contractAddr {
                    Button(action: { text.wrappedValue = "" }) {
                        Image("trash_20").renderingMode(.template)
                    }
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

    @ViewBuilder
    private var logoSetting: some View {
        if let logoViewModel {
            NavigationLink {
                SafeDappLogoView(viewModel: logoViewModel)
            } label: {
                HStack {
                    Text("safe_dapp.logo".localized.uppercased())
                        .themeSubhead1(color: .themeLeah)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.themeGray)
                }
                .padding(.horizontal, .margin16)
                .padding(.vertical, .margin16)
            }
            .buttonStyle(.plain)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
        }
    }
}
