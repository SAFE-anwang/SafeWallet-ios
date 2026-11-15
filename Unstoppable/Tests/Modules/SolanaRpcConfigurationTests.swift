import XCTest
@testable import WalletCore

final class SolanaRpcConfigurationTests: XCTestCase {
    func testMissingOrEmptyAlchemyKeysDisableAlchemySource() {
        XCTAssertEqual(AppConfig.solanaAlchemyApiKeys(from: nil), [])
        XCTAssertEqual(AppConfig.solanaAlchemyApiKeys(from: ""), [])
        XCTAssertEqual(AppConfig.solanaAlchemyApiKeys(from: " , \n , "), [])
    }

    func testAlchemyKeysAreTrimmedAndEmptyEntriesAreIgnored() {
        XCTAssertEqual(
            AppConfig.solanaAlchemyApiKeys(from: " key-one, ,\nkey-two  "),
            ["key-one", "key-two"]
        )
    }

    func testRemoteRpcRequiresSolNetworkAndValidHttpsEndpoint() {
        XCTAssertNil(SolanaRpcSourceManager.remoteRpcSource(
            network: "eth", endpoint: "https://solana-mainnet.core.chainstack.com/rpc-key"
        ))
        XCTAssertNil(SolanaRpcSourceManager.remoteRpcSource(network: "sol", endpoint: "http://rpc.example.com"))
        XCTAssertNil(SolanaRpcSourceManager.remoteRpcSource(network: "sol", endpoint: "https://"))
        XCTAssertNil(SolanaRpcSourceManager.remoteRpcSource(network: "sol", endpoint: "https://user:pass@rpc.example.com"))
    }

    func testRemoteSolRpcBuildsMainnetSource() throws {
        let source = try XCTUnwrap(SolanaRpcSourceManager.remoteRpcSource(
            network: "sol", endpoint: " https://solana-mainnet.core.chainstack.com/rpc-key "
        ))

        XCTAssertEqual(source.url.absoluteString, "https://solana-mainnet.core.chainstack.com/rpc-key")
        XCTAssertEqual(source.name, "Remote Solana RPC")
        XCTAssertTrue(source.isMainnet)
    }

    func testEndpointUpdatesReportOnlyChangedNetworks() {
        let oldSolEndpoint = RpcEndpoint(
            id: "sol-mainnet", endpoint: "https://rpc-old.example.com", network: "sol", networkId: "101", type: "http"
        )
        let ethEndpoint = RpcEndpoint(
            id: "eth-mainnet", endpoint: "https://eth-old.example.com", network: "eth", networkId: "1", type: "http"
        )
        let updatedEthEndpoint = RpcEndpoint(
            id: "eth-mainnet", endpoint: "https://eth-new.example.com", network: "eth", networkId: "1", type: "http"
        )
        let bscEndpoint = RpcEndpoint(
            id: "bsc-mainnet", endpoint: "https://bsc.example.com", network: "bsc", networkId: "56", type: "http"
        )

        XCTAssertEqual(
            ApiKeyService.updatedRpcNetworks(
                from: [oldSolEndpoint, ethEndpoint],
                to: [oldSolEndpoint, updatedEthEndpoint, bscEndpoint]
            ),
            [.eth, .bsc]
        )
        XCTAssertTrue(ApiKeyService.updatedRpcNetworks(from: [oldSolEndpoint], to: [oldSolEndpoint]).isEmpty)
        let sameUrlWithNewId = RpcEndpoint(
            id: "rotated-id", endpoint: oldSolEndpoint.endpoint, network: "sol", networkId: "101", type: "http"
        )
        XCTAssertTrue(ApiKeyService.updatedRpcNetworks(from: [oldSolEndpoint], to: [sameUrlWithNewId]).isEmpty)
    }

    func testRemoteRpcUpdatesRouteToTheirActiveBlockchains() {
        XCTAssertEqual(
            EvmSyncSourceManager.blockchainTypes(
                for: [.eth, .bsc, .p2pify, .polygon, .avax, .optimism, .arbitrum, .gnosis, .fantom],
                testNetEnabled: false,
                safe4IsTestNet: false
            ),
            [.ethereum, .binanceSmartChain, .polygon, .avalanche, .optimism, .arbitrumOne, .gnosis, .fantom]
        )
        XCTAssertEqual(
            EvmSyncSourceManager.blockchainTypes(
                for: [.safe4, .safe4_testnet, .sol],
                testNetEnabled: false,
                safe4IsTestNet: false
            ),
            [.safe4]
        )
        XCTAssertEqual(
            EvmSyncSourceManager.blockchainTypes(
                for: [.eth, .bsc, .p2pify, .safe4, .safe4_testnet],
                testNetEnabled: true,
                safe4IsTestNet: true
            ),
            [.safe4]
        )
    }
}
