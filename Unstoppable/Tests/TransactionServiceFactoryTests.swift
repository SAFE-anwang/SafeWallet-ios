import BigInt
import Combine
import EvmKit
import Foundation
import MarketKit
import Testing
@testable import WalletCore

@Suite(.serialized)
struct TransactionServiceFactoryTests {
    private func input(_ suffix: String) throws -> (SendData, Token) {
        let token = Token(
            coin: Coin(uid: "factory-regression-" + suffix, name: "Factory fixture", code: "TEST"),
            blockchain: Blockchain(type: .ethereum, name: "Ethereum", explorerUrl: nil),
            type: .native, decimals: 18
        )
        let transaction = try TransactionData(to: EvmKit.Address(hex: "0x" + String(repeating: "1", count: 40)), value: 0, input: Data())
        return (.evm(blockchainType: .ethereum, transactionData: transaction, token: token), token)
    }

    // Providers match only these synthetic coin IDs and never create a wallet or broadcast.
    @Test @MainActor func prependedProviderReceivesOriginalSettings() throws {
        TransactionServiceFactory.prepend(FactoryProbeProvider.self)
        let (sendData, token) = try input("prepend")
        let service = TransactionServiceFactory.transactionService(
            sendData: sendData, baseToken: token, initialTransactionSettings: .evm(gasPrice: nil, nonce: 73)
        )
        let probe = try #require(service as? FactoryProbeService)
        #expect(probe.provider == "primary")
        #expect(probe.nonce == 73)
    }

    @Test @MainActor func decliningProviderFallsThroughToRegisteredProvider() throws {
        TransactionServiceFactory.register(FactoryFallbackProvider.self)
        TransactionServiceFactory.prepend(FactoryProbeProvider.self)
        let (sendData, token) = try input("fallback")
        let service = TransactionServiceFactory.transactionService(sendData: sendData, baseToken: token, initialTransactionSettings: nil)
        #expect((service as? FactoryProbeService)?.provider == "fallback")
    }

    @Test @MainActor func firstMatchingProviderWins() throws {
        TransactionServiceFactory.register(FactoryFallbackProvider.self)
        TransactionServiceFactory.prepend(FactoryProbeProvider.self)
        let (sendData, token) = try input("precedence")
        let service = TransactionServiceFactory.transactionService(sendData: sendData, baseToken: token, initialTransactionSettings: nil)
        #expect((service as? FactoryProbeService)?.provider == "primary")
    }
}

private final class FactoryProbeProvider: TransactionService {
    override class func instance(sendData: SendData, baseToken: Token, initialTransactionSettings: InitialTransactionSettings?) -> ITransactionService? {
        guard ["factory-regression-prepend", "factory-regression-precedence"].contains(baseToken.coin.uid),
              case let .evm(_, _, token) = sendData, token == baseToken else { return nil }
        let nonce: Int?
        if case let .evm(_, value)? = initialTransactionSettings { nonce = value } else { nonce = nil }
        return FactoryProbeService(provider: "primary", nonce: nonce)
    }
}

private final class FactoryFallbackProvider: TransactionService {
    override class func instance(sendData: SendData, baseToken: Token, initialTransactionSettings: InitialTransactionSettings?) -> ITransactionService? {
        guard ["factory-regression-fallback", "factory-regression-precedence"].contains(baseToken.coin.uid) else { return nil }
        return FactoryProbeService(provider: "fallback", nonce: nil)
    }
}

private struct FactoryProbeService: ITransactionService {
    let provider: String
    let nonce: Int?
    var transactionSettings: TransactionSettings? { nil }
    var modified: Bool { false }
    var cautions: [CautionNew] { [] }
    var updatePublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    func sync() async throws {}
}
