import Combine
import Foundation

class MainSafeZoneViewModel: ObservableObject {
    let crossChainManager = Core.shared.safeCrossChainManager

    func getConfig() {
        crossChainManager.getConfig()
    }
}
