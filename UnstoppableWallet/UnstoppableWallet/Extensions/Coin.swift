import MarketKit
import UIKit

extension Coin {
    var imageUrl: String {
        let scale = Int(UIScreen.main.scale)
        return uid.isSafeCoin ? "https://anwang.com/img/logos/safe.png" : "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
    }
}
