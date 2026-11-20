import MarketKit
import UIKit

extension Coin {
    var isSafe4Native: Bool {
        uid.caseInsensitiveCompare(safe4CoinUid) == .orderedSame
    }

    var imageUrl: String {
        Self.imageUrl(uid: uid)
    }

    public static func imageUrl(uid: String) -> String {
        let scale = Int(UIScreen.main.scale)
        if uid.contains("custom-safe4-anwang") || uid.contains("custom-safe-anwang") || uid.isSafeCoin {
            if let logoUrl = SRC20SyncManager.logo(coinUid: uid.lowercased()) {
                return logoUrl.count > 0 ? logoUrl : "https://anwang.com/img/logos/safe.png"
            }
            return "https://anwang.com/img/logos/safe.png"
        }
        return "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
    }

    // Same rule as the server: a coin re-listed on another chain keeps the original coingecko_id
    var isSynthetic: Bool {
        guard let coinGeckoId else { return false }
        return coinGeckoId != uid
    }
}
