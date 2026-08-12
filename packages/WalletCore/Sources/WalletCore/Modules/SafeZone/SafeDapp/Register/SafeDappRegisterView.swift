import SwiftUI
import UIKit

struct SafeDappRegisterView: View {
    @StateObject var viewModel: SafeDappRegisterViewModel
    @FocusState private var focusedField: SafeDappField?
    @State private var showConfirm = false
    @Binding private var isPresented: Bool

    init(viewModel: SafeDappRegisterViewModel, isPresented: Binding<Bool>) {
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
                                input(title: SafeDappField.name.title, text: $viewModel.form.name, field: .name, caution: $viewModel.nameCautionState)
                                input(title: SafeDappField.contractAddr.title, text: $viewModel.form.contractAddr, field: .contractAddr, caution: $viewModel.contractCautionState)
                                input(title: SafeDappField.runUrl.title, text: $viewModel.form.runUrl, field: .runUrl, caution: $viewModel.runUrlCautionState, keyboardType: .URL)
                                input(title: SafeDappField.description.title, text: $viewModel.form.description, field: .description, caution: $viewModel.descriptionCautionState, lineLimit: 4)
                                input(title: SafeDappField.gitUrl.title, text: $viewModel.form.gitUrl, field: .gitUrl, caution: $viewModel.gitUrlCautionState, keyboardType: .URL)
                                input(title: SafeDappField.officialUrl.title, text: $viewModel.form.officialUrl, field: .officialUrl, caution: $viewModel.officialUrlCautionState, keyboardType: .URL)
                                input(title: SafeDappField.officialEmail.title, text: $viewModel.form.officialEmail, field: .officialEmail, caution: $viewModel.officialEmailCautionState, keyboardType: .emailAddress)
                            }
                            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin16, trailing: .margin16))
                        }
                    } bottomContent: {
                        Button(action: {
                            if viewModel.validateForSubmit() {
                                showConfirm = true
                            }
                        }) {
                            Text("safe_dapp.register".localized)
                        }
                        .disabled(viewModel.sendState == .sending)
                        .buttonStyle(PrimaryButtonStyle(style: .yellow))
                    }

                    if viewModel.sendState == .sending {
                        ProgressView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { isPresented = false }) { Image("close") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("button.done".localized) { focusedField = nil }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
            .navigationBarTitle("safe_dapp.register".localized)
            .navigationBarTitleDisplayMode(.inline)
            .alert("safe_dapp.register_confirm".localized, isPresented: $showConfirm, actions: {
                Button("button.cancel".localized) {}
                Button("button.confirm".localized) {
                    viewModel.register { state in
                        switch state {
                        case .completed:
                            HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                            isPresented = false
                        case let .failed(message):
                            HudHelper.instance.show(banner: .error(string: message))
                        default: ()
                        }
                    }
                }
            })
        }
    }

    @ViewBuilder
    private func input(title: String, text: Binding<String>, field: SafeDappField, caution: Binding<CautionState>, keyboardType: UIKeyboardType = .default, lineLimit: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: .margin8) {
            Text(title.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))

            HStack(spacing: .margin8) {
                if lineLimit == 1 {
                    TextField("", text: text)
                        .foregroundColor(.themeLeah)
                        .font(.themeHeadline1)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: field)
                } else {
                    TextEditor(text: text)
                        .foregroundColor(.themeLeah)
                        .font(.themeHeadline1)
                        .frame(minHeight: 96)
                        .focused($focusedField, equals: field)
                }

                if !text.wrappedValue.isEmpty {
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
}
