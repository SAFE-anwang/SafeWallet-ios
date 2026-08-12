import EvmKit
import Foundation
import SwiftUI
import UIKit
import web3swift

enum SafeDappModule {
    private static func service() -> SafeDappService? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        return SafeDappService(
            privateKey: privateKey,
            userAddress: evmKitWrapper.evmKit.receiveAddress.hex,
            chainId: evmKitWrapper.evmKit.chain.id
        )
    }

    static func registerViewModel() -> SafeDappRegisterViewModel? {
        guard let service = service() else { return nil }
        return SafeDappRegisterViewModel(service: service)
    }

    static func managerViewModel() -> SafeDappManagerViewModel? {
        guard let service = service() else { return nil }
        return SafeDappManagerViewModel(service: service)
    }

    static func editViewModel(info: DAppInfo) -> SafeDappEditViewModel? {
        guard let service = service() else { return nil }
        return SafeDappEditViewModel(info: info, service: service)
    }

    static func logoViewModel(info: DAppInfo, currentLogo: UIImage?) -> SafeDappLogoViewModel? {
        guard let service = service() else { return nil }
        return SafeDappLogoViewModel(info: info, currentLogo: currentLogo, service: service)
    }
}
