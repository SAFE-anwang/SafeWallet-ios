import UIKit

struct SuperNodeRegisterModule {
    static func viewController() -> UIViewController? {
        
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = SuperNodeRegisterService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeRegisterViewModel(service: service, decimalParser: AmountDecimalParser())
        return SuperNodeRegisterViewController(viewModel: viewModel)
    }
}

