import Foundation
import GRDB
import MarketKit
import Testing
@testable import WalletCore

private struct Safe4SRC20TokenClassifierTestEnvironment {
    let storage: Safe4CustomTokenStorage
    let classifier: Safe4SRC20TokenClassifier

    init() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-src20-classifier-tests-\(UUID().uuidString).sqlite")
        let dbPool = try DatabasePool(path: databaseURL.path)
        let storage = try Safe4CustomTokenStorage(dbPool: dbPool)

        self.storage = storage
        classifier = Safe4SRC20TokenClassifier(storage: storage)
    }
}

struct Safe4SRC20TokenClassifierTests {
    private let address = "0x1111111111111111111111111111111111111111"
    private let mainNetChainId = 666
    private let testNetChainId = 667

    @Test func recognizesOnlyCustomTokenOnMatchingChain() throws {
        let environment = try Safe4SRC20TokenClassifierTestEnvironment()
        let query = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: address))

        #expect(!environment.classifier.isSRC20(tokenQuery: query, chainId: mainNetChainId))

        environment.storage.save(token: Safe4CustomTokenRecord(
            address: address,
            symbol: "SRC",
            creator: "0x2222222222222222222222222222222222222222",
            chainId: mainNetChainId,
            decimals: 18,
            name: "SRC Token"
        ))

        #expect(environment.classifier.isSRC20(tokenQuery: query, chainId: mainNetChainId))
        #expect(!environment.classifier.isSRC20(tokenQuery: query, chainId: testNetChainId))
    }
}
