import Combine

class TermsViewModel: ObservableObject {
    private let termsManager = Core.shared.termsManager

    let termsAccepted: Bool

    init() {
        termsAccepted = termsManager.termsAccepted
        Core.shared.marketKit.sync()
    }
}

extension TermsViewModel {
    func setTermsAccepted() {
        termsManager.setTermsAccepted()
    }
}
