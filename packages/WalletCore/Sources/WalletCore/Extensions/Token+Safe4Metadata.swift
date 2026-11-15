import MarketKit

extension Token {
    /// Older MarketKit and enabled-wallet records label the wrapped contract as SAFE.
    /// Resolve its display metadata by chain and contract, preserving the asset identity.
    var withCanonicalSafe4Metadata: Token {
        guard blockchainType == .safe4,
              case let .eip20(address) = type,
              address.lowercased() == "0x0000000000000000000000000000000000001101",
              coin.code != "WSAFE" || coin.name != "Wrapped SAFE"
        else {
            return self
        }

        return Token(
            coin: Coin(
                uid: coin.uid,
                name: "Wrapped SAFE",
                code: "WSAFE",
                marketCapRank: coin.marketCapRank,
                coinGeckoId: coin.coinGeckoId,
                image: coin.image
            ),
            blockchain: blockchain,
            type: type,
            decimals: decimals
        )
    }
}
