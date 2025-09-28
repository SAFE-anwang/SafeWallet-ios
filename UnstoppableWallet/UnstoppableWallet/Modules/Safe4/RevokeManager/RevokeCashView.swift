import SwiftUI
@preconcurrency import WebKit

struct RevokeCashView: View {

    @StateObject private var viewModel: RevokeCashViewModel
    @State private var reloadTrigger = 0
    
    init(viewModel: RevokeCashViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    var body: some View {
        ThemeView {
            Web3WebView(viewModel: viewModel, reloadTrigger: $reloadTrigger)
        }
        .navigationTitle("Revoke_Manager".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.presentDestination, onDismiss: {
            reloadTrigger += 1
        }) { present in
            switch present {
            case let .toConfirmation(vc):
                SendEvmConfirmationView(viewController: vc)
            }
        }
        .onAppear() {
            viewModel.make()
        }
    }
}

struct Web3WebView: UIViewRepresentable {

    let viewModel: RevokeCashViewModel
    @Binding var reloadTrigger: Int
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: viewModel.config)
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: viewModel.dappUrl)
        webView.load(request)
        
        if context.coordinator.lastReloadTrigger != reloadTrigger {
            webView.reload()
            context.coordinator.lastReloadTrigger = reloadTrigger
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, reloadTrigger: reloadTrigger)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: Web3WebView
        private var hasInjected = false
        var lastReloadTrigger: Int
        
        init(_ parent: Web3WebView, reloadTrigger: Int) {
            self.parent = parent
            self.lastReloadTrigger = reloadTrigger
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            
        }

    }
}




