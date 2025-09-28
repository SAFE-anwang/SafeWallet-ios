import MarketKit
import UIKit

extension Coin {
    var imageUrl: String {
        let scale = Int(UIScreen.main.scale)
        if uid.contains("custom-safe4-anwang") || uid.contains("custom-safe-anwang") || uid.isSafeCoin {
            if let logoUrl = SRC20SyncManager.logo(coinUid: uid.lowercased()) {
                return logoUrl
            }
            return "https://anwang.com/img/logos/safe.png"
        }else {
            return "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
        }
    }
}
