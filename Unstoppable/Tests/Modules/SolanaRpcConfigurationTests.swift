import MarketKit
import SolanaKit
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

        let changes = ApiKeyService.updatedRpcEndpoints(
            from: [oldSolEndpoint, ethEndpoint],
            to: [oldSolEndpoint, updatedEthEndpoint, bscEndpoint]
        )
        XCTAssertEqual(changes.map(\.network), [.eth, .bsc])
        XCTAssertEqual(changes.map(\.previousEndpoint), [ethEndpoint.endpoint, nil])
        XCTAssertEqual(changes.map(\.endpoint), [updatedEthEndpoint.endpoint, bscEndpoint.endpoint])
        XCTAssertTrue(ApiKeyService.updatedRpcEndpoints(from: [oldSolEndpoint], to: [oldSolEndpoint]).isEmpty)
        let sameUrlWithNewId = RpcEndpoint(
            id: "rotated-id", endpoint: oldSolEndpoint.endpoint, network: "sol", networkId: "101", type: "http"
        )
        XCTAssertTrue(ApiKeyService.updatedRpcEndpoints(from: [oldSolEndpoint], to: [sameUrlWithNewId]).isEmpty)
    }

    func testRemoteRpcUpdatesRefreshOnlyActiveBlockchainsAndDeduplicate() {
        XCTAssertEqual(
            EvmSyncSourceManager.blockchainTypesToRefresh(
                for: [.eth, .bsc, .p2pify, .polygon, .avax, .optimism, .arbitrum, .gnosis, .fantom],
                testNetEnabled: false,
                safe4IsTestNet: false
            ),
            [.ethereum, .binanceSmartChain, .polygon, .avalanche, .optimism, .arbitrumOne, .gnosis, .fantom]
        )
        XCTAssertEqual(
            EvmSyncSourceManager.blockchainTypesToRefresh(
                for: [.safe4, .safe4_testnet, .sol],
                testNetEnabled: false,
                safe4IsTestNet: false
            ),
            [.safe4]
        )
        XCTAssertEqual(
            EvmSyncSourceManager.blockchainTypesToRefresh(
                for: [.eth, .bsc, .p2pify, .safe4, .safe4_testnet],
                testNetEnabled: true,
                safe4IsTestNet: true
            ),
            [.safe4]
        )
        XCTAssertEqual(EvmSyncSourceManager.blockchainType(for: .eth), .ethereum)
        XCTAssertEqual(EvmSyncSourceManager.blockchainType(for: .bsc), .binanceSmartChain)
        XCTAssertEqual(EvmSyncSourceManager.blockchainType(for: .p2pify), .binanceSmartChain)
        XCTAssertEqual(EvmSyncSourceManager.blockchainType(for: .safe4), .safe4)
        XCTAssertEqual(EvmSyncSourceManager.blockchainType(for: .safe4_testnet), .safe4)
        XCTAssertNil(EvmSyncSourceManager.blockchainType(for: .sol))
    }

    func testEndpointRotationMigratesOnlyTheCurrentlySelectedRemoteEndpoint() {
        for invalid in ["", "/relative", "https://", "https://["] {
            XCTAssertNil(ApiKeyManager.validHttpEndpoint(invalid))
            XCTAssertNil(EvmSyncSourceManager.migratedSelectedEndpoint(
                current: "https://old.example", previous: "https://old.example", updated: invalid
            ))
        }
        for valid in ["http://localhost:8545", "https://rpc.example/path?key=example"] {
            XCTAssertEqual(ApiKeyManager.validHttpEndpoint(valid), valid)
        }
        XCTAssertEqual(
            EvmSyncSourceManager.migratedSelectedEndpoint(
                current: "https://p2pify-old.example.com/rpc",
                previous: "https://p2pify-old.example.com/rpc",
                updated: "https://p2pify-new.example.com/rpc"
            ),
            "https://p2pify-new.example.com/rpc"
        )
        XCTAssertNil(EvmSyncSourceManager.migratedSelectedEndpoint(
            current: "https://blocksdecoded.example.com/rpc",
            previous: "https://eth-old.example.com/rpc",
            updated: "https://eth-new.example.com/rpc"
        ))
        XCTAssertNil(EvmSyncSourceManager.migratedSelectedEndpoint(
            current: "https://custom.example.com/rpc",
            previous: "https://p2pify-old.example.com/rpc",
            updated: "https://p2pify-new.example.com/rpc"
        ))
        XCTAssertNil(EvmSyncSourceManager.migratedSelectedEndpoint(
            current: "https://p2pify-old.example.com/rpc",
            previous: "https://p2pify-old.example.com/rpc",
            updated: nil
        ))
    }
}
