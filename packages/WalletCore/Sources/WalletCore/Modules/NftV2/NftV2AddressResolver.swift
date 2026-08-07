import Foundation

struct NftV2AddressContext {
    let chain: NftV2Chain
    let address: String
}

final class NftV2AddressResolver {
    private let evmBlockchainManager: EvmBlockchainManager

    init(evmBlockchainManager: EvmBlockchainManager) {
        self.evmBlockchainManager = evmBlockchainManager
    }

    func addressContexts(account: Account) -> [NftV2Chain: NftV2AddressContext] {
        var result = [NftV2Chain: NftV2AddressContext]()

        for chain in NftV2Chain.allCases {
            guard let evmChain = try? evmBlockchainManager.chain(blockchainType: chain.blockchainType) else {
                continue
            }

            let address: String
            do {
                if let childAddress = try ChildWalletBridge.shared.evmAddress(account: account, blockchainType: chain.blockchainType, chain: evmChain) {
                    address = childAddress.eip55
                } else if let rootAddress = try account.type.evmAddress(chain: evmChain) {
                    address = rootAddress.eip55
                } else {
                    continue
                }
            } catch {
                continue
            }

            result[chain] = NftV2AddressContext(chain: chain, address: address)
        }

        return result
    }
}
