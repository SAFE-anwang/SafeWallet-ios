import EvmKit
import Foundation
import MarketKit
import UIKit

extension TransactionRecord {
    var isSafe4Incoming: Bool {
        guard source.blockchainType == .safe4 else {return false}
        switch self {
        case let record as ContractCallTransactionRecord:
            guard let input = record.transaction.input else {return false}
            let method = Data(input.prefix(4)).hs.hexString
            return method == EvmKit.Safe4Methods.Reward.id
        default: return false
        }
    }

    var isNodestatus: Bool {
        guard source.blockchainType == .safe4 else {return false}
        switch self {
        case let record as EvmTransactionRecord:
            guard let input = record.transaction.input else {return false}
            let method = Data(input.prefix(4)).hs.hexString
            return method == EvmKit.Safe4Methods.NodeStateUpload.id
        default: return false
        }
    }
}

extension TransactionRecord {
    func imageUrl(coinUid: String) -> String {
        if source.blockchainType == .safe4 || source.blockchainType == .safe {
            if let logoUrl = SRC20SyncManager.logo(coinUid: coinUid.lowercased()) {
                return logoUrl
            }
            return "https://anwang.com/img/logos/safe.png"
        }else if uid == dogeCoinUid {
            let scale = Int(UIScreen.main.scale)
            return "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
        }else {
            let scale = Int(UIScreen.main.scale)
            return "https://cdn.blocksdecoded.com/blockchain-icons/32px/\(uid)@\(scale)x.png"
        }
    }
    var imageUrl: String {
        if source.blockchainType == .safe4 || source.blockchainType == .safe {
            return "https://anwang.com/img/logos/safe.png"
        }else if uid == dogeCoinUid {
            let scale = Int(UIScreen.main.scale)
            return "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
        }else {
            let scale = Int(UIScreen.main.scale)
            return "https://cdn.blocksdecoded.com/blockchain-icons/32px/\(uid)@\(scale)x.png"
        }
    }
}
