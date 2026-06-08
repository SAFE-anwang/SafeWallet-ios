import SwiftUI
import UIKit

struct MarketDappView: View {
    @StateObject var viewModel: MarketDappViewModel
    @StateObject private var riskChecker = UrlRiskChecker()
    @State private var loadedTabs = [MarketDappModule.Tab]()
    @State private var dappUrl = ""
    @State private var urlAlert: DappUrlAlert?

    init(viewModel: MarketDappViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: .margin8) {
                Image("search").icon()

                DappUrlInputField(
                    placeholder: "safe_dapp.input".localized,
                    text: $dappUrl,
                    onSubmit: openInputUrl
                )

                if !dappUrl.isEmpty {
                    IconButton(icon: "trash_filled", style: .secondary, mode: .transparent, size: .small) {
                        dappUrl = ""
                    }
                }
            }
            .padding(.horizontal, .margin16)
            .frame(height: 48)
            .background(Color.themeBlade)
            .clipShape(Capsule(style: .continuous))
            .padding(.horizontal, .margin16)
            .padding(.top, .margin8)
            .padding(.bottom, .margin12)

            ScrollableTabHeaderView(
                tabs: MarketDappModule.Tab.allCases.map {
                    ScrollableTabHeaderView.Tab(
                        title: $0.title,
                        highlighted: false
                    )
                },
                currentTabIndex: Binding(
                    get: {
                        MarketDappModule.Tab.allCases.firstIndex(of: viewModel.currentTab) ?? 0
                    },
                    set: { index in
                        viewModel.currentTab = MarketDappModule.Tab.allCases[index]
                    }
                ),
                isAequilate: true
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )

            ZStack {
                ForEach(MarketDappModule.Tab.allCases, id: \.id) { tab in
                    MarketDappListView(tab: tab)
                        .tag(tab.id)
                        .ignoresSafeArea()
                        .opacity(viewModel.currentTab == tab ? 1 : 0)
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
        }
        .alert(item: $urlAlert) { alert in
            if let url = alert.url {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("button.continue".localized)) {
                        MarketDappModule.open(url: url, tab: viewModel.currentTab)
                    },
                    secondaryButton: .cancel(Text("button.cancel".localized))
                )
            } else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("button.ok".localized))
                )
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openInputUrl() {
        guard let normalizedUrl = MarketDappModule.normalizedUrl(from: dappUrl) else {
            urlAlert = DappUrlAlert.invalidUrl
            return
        }

        dappUrl = normalizedUrl.absoluteString

        switch riskChecker.check(url: normalizedUrl) {
        case .secure, .disabled:
            MarketDappModule.open(url: normalizedUrl, tab: viewModel.currentTab)
        case .risky:
            urlAlert = DappUrlAlert.risky(url: normalizedUrl)
        case .notAvailable:
            urlAlert = DappUrlAlert.notAvailable(url: normalizedUrl)
        }
    }
}

private struct DappUrlAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let url: URL?

    static var invalidUrl: DappUrlAlert {
        DappUrlAlert(
            title: "wallet_connect.error.invalid_url".localized,
            message: "wallet_connect.error.invalid_url".localized,
            url: nil
        )
    }

    static func risky(url: URL) -> DappUrlAlert {
        DappUrlAlert(
            title: "wallet_connect.main.premium_alert.title.risky".localized,
            message: "wallet_connect.main.premium_alert.subtitle.risky".localized,
            url: url
        )
    }

    static func notAvailable(url: URL) -> DappUrlAlert {
        DappUrlAlert(
            title: "wallet_connect.scam_protection".localized,
            message: "wallet_connect.main.premium_alert.subtitle.not_available".localized,
            url: url
        )
    }
}

private struct DappUrlInputField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.font = .body
        textField.textColor = .themeLeah
        textField.tintColor = .themeInputFieldTintColor
        textField.keyboardAppearance = .themeDefault
        textField.keyboardType = .URL
        textField.returnKeyType = .go
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = .URL
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.themeGray]
        )
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            text = textField.text ?? ""
            textField.resignFirstResponder()
            onSubmit()
            return false
        }
    }
}
