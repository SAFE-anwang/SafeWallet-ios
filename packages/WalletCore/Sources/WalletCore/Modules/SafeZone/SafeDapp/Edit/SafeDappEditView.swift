import SwiftUI

struct SafeDappEditView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject var viewModel: SafeDappEditViewModel
    @FocusState private var focusedField: SafeDappField?
    @State private var confirmField: SafeDappField?

    init(viewModel: SafeDappEditViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ThemeView {
            ZStack {
                ScrollableThemeView {
                    VStack(spacing: .margin8) {
                        ForEach(SafeDappField.allCases) { field in
                            fieldRow(field)
                        }
                    }
                    .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
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
        .alert("safe_dapp.update_confirm".localized, isPresented: Binding(
            get: { confirmField != nil },
            set: { if !$0 { confirmField = nil } }
        ), actions: {
            Button("button.cancel".localized, role: .cancel) { confirmField = nil }
            Button("button.confirm".localized) {
                guard let field = confirmField else { return }
                viewModel.update(field: field) { state in
                    switch state {
                    case .completed:
                        HudHelper.instance.show(banner: .success(string: "alert.sent".localized))
                        presentationMode.wrappedValue.dismiss()
                    case let .failed(message):
                        HudHelper.instance.show(banner: .error(string: message))
                    default: ()
                    }
                }
                confirmField = nil
            }
        })
    }

    @ViewBuilder
    private func fieldRow(_ field: SafeDappField) -> some View {
        let valueBox = viewModel.binding(for: field)
        let cautionBox = viewModel.cautionBinding(for: field)
        let value = Binding<String>(get: valueBox.get, set: valueBox.set)
        let caution = Binding<CautionState>(get: cautionBox.get, set: cautionBox.set)

        VStack(alignment: .leading, spacing: .margin8) {
            Text(field.title.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))

            VStack(spacing: .margin8) {
                HStack(spacing: .margin8) {
                    if field == .description {
                        TextEditor(text: value)
                            .foregroundColor(.themeLeah)
                            .font(.themeHeadline1)
                            .frame(minHeight: 96)
                            .focused($focusedField, equals: field)
                    } else {
                        TextField("", text: value)
                            .foregroundColor(.themeLeah)
                            .font(.themeHeadline1)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: field)
                    }
                    if !value.wrappedValue.isEmpty {
                        Button(action: { value.wrappedValue = "" }) {
                            Image("trash_20").renderingMode(.template)
                        }
                        .buttonStyle(SecondaryCircleButtonStyle(style: .default))
                    }
                }
                Button(action: {
                    if viewModel.prepareUpdate(field: field) {
                        confirmField = field
                    }
                }) {
                    Text("safe_dapp.update_field".localized)
                        .themeSubhead1(color: .themeLeah, alignment: .center)
                }
                .buttonStyle(PrimaryButtonStyle(style: .yellow))
            }
            .padding(.horizontal, .margin16)
            .padding(.vertical, .margin8)
            .modifier(ThemeListStyleModifier(cornerRadius: .cornerRadius8))
            .modifier(CautionBorder(cautionState: caution))
            .modifier(CautionPrompt(cautionState: caution))
        }
    }
}
