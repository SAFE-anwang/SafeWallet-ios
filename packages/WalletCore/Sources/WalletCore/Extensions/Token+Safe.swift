import MarketKit

extension Token {
    func isSafeUSDT() -> Bool {
        if case let .eip20(address) = type {
            return address.isSafeUsdtContract
        }else {
            return false
        }
    }

    var safePlaceholderImageName: String? {
        [.safe, .safe4].contains(blockchainType) ? "safe-anwang_trx_32" : nil
    }

    var placeholderImageName: String {
        safePlaceholderImageName ?? "placeholder_circle_32"
    }

    var swappable: Bool {
        BlockchainType.swappable.contains(blockchainType)
    }
}

extension Token {
    var isSafe4Native: Bool {
        coin.uid.lowercased() == safe4CoinUid.lowercased() && blockchain.type == .safe4 && type == .native
    }
    var isSafe4ETH: Bool {
        coin.uid.lowercased() == safe4CoinUid_eth.lowercased() && blockchain.type == .safe4
    }

    var isSafe4BSC: Bool {
        coin.uid.lowercased() == safe4CoinUid_bsc.lowercased() && blockchain.type == .safe4
    }

    var isSafe4POL: Bool {
        coin.uid.lowercased() == safe4CoinUid_pol.lowercased() && blockchain.type == .safe4
    }

    var isSafe4SRC: Bool {
        coin.uid.lowercased() == safe4CoinUid_src.lowercased() && blockchain.type == .safe4
    }

    var isSafe4USDT: Bool {
        coin.uid.lowercased() == safe4UsdtCoinUid.lowercased() && blockchain.type == .safe4
    }
}
