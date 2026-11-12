import UIKit
import SwiftUI

struct ProposalCreateModule {
    static func viewModel(privateKey: Data, chainId: Int) -> ProposalCreateViewModel {
        let service = ProposalCreateService(privateKey: privateKey, chainId: chainId)
        let viewModel = ProposalCreateViewModel(service: service)
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
