import UIKit

struct MasterNodeRegisterModule {
    static func viewController() -> UIViewController? {
        
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = MasterNodeRegisterService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeRegisterViewModel(service: service, decimalParser: AmountDecimalParser())
        return MasterNodeRegisterViewController(viewModel: viewModel)
    }
}
