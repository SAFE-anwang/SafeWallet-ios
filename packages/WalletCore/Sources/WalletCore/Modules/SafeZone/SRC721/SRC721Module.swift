import EvmKit
import Foundation

@MainActor
enum SRC721Module {
    private static func context(requireSigner: Bool = false) -> (evmKitWrapper: EvmKitWrapper, privateKey: Data, accountId: String)? {
        guard let accountId = Core.shared.accountManager.activeAccount?.id,
              let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard !requireSigner || evmKitWrapper.signer != nil else { return nil }
        let privateKey = evmKitWrapper.signer?.privateKey ?? Data()
        return (evmKitWrapper, privateKey, accountId)
    }

    static func deployViewModel() -> SRC721DeployViewModel? {
        guard let context = context(requireSigner: true), !context.privateKey.isEmpty else { return nil }
        let service = SRC721Service(
            privateKey: context.privateKey,
            userAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55,
            chainId: context.evmKitWrapper.evmKit.chain.id
        )
        return SRC721DeployViewModel(
            service: service,
            storage: .shared,
            accountId: context.accountId,
            walletAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55
        )
    }

    static func managerViewModel() -> SRC721ManagerViewModel? {
        guard let context = context() else { return nil }
        let service = SRC721Service(
            privateKey: context.privateKey,
            userAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55,
            chainId: context.evmKitWrapper.evmKit.chain.id
        )
        return SRC721ManagerViewModel(
            service: service,
            storage: .shared,
            accountId: context.accountId,
            walletAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55
        )
    }

    static func importViewModel() -> SRC721ImportViewModel? {
        guard let context = context() else { return nil }
        let service = SRC721Service(
            privateKey: context.privateKey,
            userAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55,
            chainId: context.evmKitWrapper.evmKit.chain.id
        )
        return SRC721ImportViewModel(
            service: service,
            storage: .shared,
            accountId: context.accountId,
            walletAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55
        )
    }

    static func detailViewModel(record: SRC721ContractRecord) -> SRC721ContractDetailViewModel? {
        guard let context = context() else { return nil }
        guard record.accountId == context.accountId,
              record.chainId == context.evmKitWrapper.evmKit.chain.id,
              record.walletAddress.lowercased() == context.evmKitWrapper.evmKit.receiveAddress.eip55.lowercased() else {
            return nil
        }
        let service = SRC721Service(
            privateKey: context.privateKey,
            userAddress: context.evmKitWrapper.evmKit.receiveAddress.eip55,
            chainId: record.chainId,
            contractAddress: record.contractAddress
        )
        return SRC721ContractDetailViewModel(record: record, service: service, storage: .shared)
    }
}
