import UIKit
import SwiftUI

struct ProposalCreateModule {
    static func viewModel(privateKey: Data) -> ProposalCreateViewModel {
        let service = ProposalCreateService(privateKey: privateKey)
        let viewModel = ProposalCreateViewModel(service: service, decimalParser: AmountDecimalParser())
        return viewModel
    }
}
struct ProposalCreateView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: ProposalCreateViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return ThemeNavigationController(rootViewController: ProposalCreateViewController(viewModel: viewModel))
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

