import UIKit

struct ProposalCreateModule {
    static func viewController(privateKey: Data) -> UIViewController {
        let service = ProposalCreateService(privateKey: privateKey)
        let viewModel = ProposalCreateViewModel(service: service, decimalParser: AmountDecimalParser())
        return ProposalCreateViewController(viewModel: viewModel)
    }
}
