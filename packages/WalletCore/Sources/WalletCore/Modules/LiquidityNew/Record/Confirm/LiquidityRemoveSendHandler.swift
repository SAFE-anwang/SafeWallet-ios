import BigInt
import Combine
import EvmKit
import Foundation
import MarketKit
import RxSwift
import UIExtensions

public final class LiquidityRemoveRequest {
    public let blockchainType: BlockchainType
    let makeHandler: () -> ISendHandler?

    public init(blockchainType: BlockchainType, makeHandler: @escaping () -> ISendHandler?) {
        self.blockchainType = blockchainType
        self.makeHandler = makeHandler
    }
}

/// Bridges the existing liquidity removal engines into the SendNew confirmation flow.
/// The service remains the source of truth for permit/approve fallbacks and transaction
/// construction; this handler waits for its terminal state instead of returning after a
/// fire-and-forget broadcast.
final class LiquidityRemoveSendHandler: ISendHandler {
    private let completion: (@escaping (Result<Void, Error>) -> Void) -> Disposable
    private let start: (TransactionSettings?) -> Void
    private var transactionSettings: TransactionSettings?
    private let makeData: (TransactionSettings?) async throws -> LiquidityRemoveSendData

    let baseToken: Token

    private init(baseToken: Token, completion: @escaping (@escaping (Result<Void, Error>) -> Void) -> Disposable, start: @escaping (TransactionSettings?) -> Void, makeData: @escaping (TransactionSettings?) async throws -> LiquidityRemoveSendData) {
        self.baseToken = baseToken
        self.completion = completion
        self.start = start
        self.makeData = makeData
    }

    static func v2(item: LiquidityRecordViewModel.RecordItem, ratio: BigUInt, service: LiquidityRecordService) -> LiquidityRemoveSendHandler? {
        guard let baseToken = try? Core.shared.coinManager.token(query: .init(blockchainType: item.tokenA.blockchainType, tokenType: .native)) else { return nil }
        return LiquidityRemoveSendHandler(
            baseToken: baseToken,
            completion: { callback in
                service.stateObservable.subscribe(onNext: { state in
                    switch state {
                    case .removeSuccess: callback(.success(()))
                    case let .failed(error): callback(.failure(LiquidityRemoveError.message(error)))
                    case let .removeFailed(error):
                        if let txHash = service.lastSubmittedTransactionHash {
                            callback(.failure(LiquidityRemovePartialError(message: error, txHash: txHash)))
                        } else {
                            callback(.failure(LiquidityRemoveError.message(error)))
                        }
                    case .approveFailed: callback(.failure(LiquidityRemoveError.message("liquidity.remove.error.execution_reverted".localized("approve"))))
                    default: break
                    }
                })
            },
            start: { settings in service.removeLiquidity(viewItem: item, ratio: ratio, transactionSettings: settings) },
            makeData: { settings in
                let fee = try await service.estimateRemoveFee(viewItem: item, ratio: ratio, transactionSettings: settings)
                return LiquidityRemoveSendData.v2(item: item, ratio: ratio, fee: fee)
            }
        )
    }

    static func v3(item: LiquidityV3RecordViewModel.V3RecordItem, ratio: BigUInt, service: LiquidityV3RecordService) -> LiquidityRemoveSendHandler? {
        guard let baseToken = try? Core.shared.coinManager.token(query: .init(blockchainType: item.token0.blockchainType, tokenType: .native)) else { return nil }
        return LiquidityRemoveSendHandler(
            baseToken: baseToken,
            completion: { callback in
                service.stateObservable.subscribe(onNext: { state in
                    switch state {
                    case .removeSuccess: callback(.success(()))
                    case let .failed(error): callback(.failure(LiquidityRemoveError.message(error)))
                    case let .removeFailed(error):
                        if let txHash = service.lastSubmittedTransactionHash {
                            callback(.failure(LiquidityRemovePartialError(message: error, txHash: txHash)))
                        } else {
                            callback(.failure(LiquidityRemoveError.message(error)))
                        }
                    case .approveFailed: callback(.failure(LiquidityRemoveError.message("liquidity.remove.error.execution_reverted".localized("approve"))))
                    default: break
                    }
                })
            },
            start: { settings in service.removeLiquidity(item: item, ratio: ratio, transactionSettings: settings) },
            makeData: { settings in
                let fee = try await service.estimateRemoveFee(item: item, ratio: ratio, transactionSettings: settings)
                return LiquidityRemoveSendData.v3(item: item, ratio: ratio, fee: fee)
            }
        )
    }

    var expirationDuration: Int? { 20 * 60 }

    func sendData(transactionSettings: TransactionSettings?) async throws -> ISendData {
        self.transactionSettings = transactionSettings
        return try await makeData(transactionSettings)
    }

    func send(data _: ISendData) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var disposable: Disposable?
            disposable = completion { result in
                disposable?.dispose()
                if case let .failure(error) = result {
                    DispatchQueue.main.async {
                        HudHelper.instance.show(banner: .error(string: error.smartDescription))
                    }
                }
                continuation.resume(with: result)
            }
            start(transactionSettings)
        }
    }
}

private enum LiquidityRemoveError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(value) = self { return value }
        return nil
    }
}

private struct LiquidityRemovePartialError: Error, LocalizedError, IPartialExecutionError {
    let message: String
    let txHash: String

    var errorDescription: String? { message }
    var partialTxHash: String? { txHash }
}

private final class LiquidityRemoveSendData: ISendData {
    private let fields: [SendField]
    private let coins: [Coin]
    private let ratio: BigUInt
    private let blockchainType: BlockchainType

    private let fee: (EvmFeeData, GasPrice)

    private init(fields: [SendField], coins: [Coin], ratio: BigUInt, blockchainType: BlockchainType, fee: (EvmFeeData, GasPrice)) {
        self.fields = fields
        self.coins = coins
        self.ratio = ratio
        self.blockchainType = blockchainType
        self.fee = fee
    }

    static func v2(item: LiquidityRecordViewModel.RecordItem, ratio: BigUInt, fee: (EvmFeeData, GasPrice)) -> LiquidityRemoveSendData {
        let percent = ratio.description + "%"
        return LiquidityRemoveSendData(
            fields: [
                .simpleValue(title: "liquidity.remove.rate.title".localized, value: percent),
                .simpleValue(title: "send.confirmation.to".localized, value: recipientAddress(blockchainType: item.tokenA.blockchainType)),
                .simpleValue(title: "swap.advanced_settings.deadline".localized, value: "swap.advanced_settings.deadline_minute".localized("20"))
            ],
            coins: [item.tokenA.coin, item.tokenB.coin],
            ratio: ratio,
            blockchainType: item.tokenA.blockchainType,
            fee: fee
        )
    }

    static func v3(item: LiquidityV3RecordViewModel.V3RecordItem, ratio: BigUInt, fee: (EvmFeeData, GasPrice)) -> LiquidityRemoveSendData {
        LiquidityRemoveSendData(
            fields: [
                .simpleValue(title: "liquidity.remove.rate.title".localized, value: ratio.description + "%"),
                .simpleValue(title: "liquidity.tick.min".localized + " / " + "liquidity.tick.max".localized, value: item.tickRangeDesc + " (" + item.state + ")"),
                .simpleValue(title: "swap.liquidity_fee".localized, value: item.fee),
                .simpleValue(title: "send.confirmation.to".localized, value: recipientAddress(blockchainType: item.token0.blockchainType)),
                .simpleValue(title: "swap.advanced_settings.deadline".localized, value: "swap.advanced_settings.deadline_minute".localized("20"))
            ],
            coins: [item.token0.coin, item.token1.coin],
            ratio: ratio,
            blockchainType: item.token0.blockchainType,
            fee: fee
        )
    }

    private static func recipientAddress(blockchainType: BlockchainType) -> String {
        ChildWalletBridge.shared.activeEvmKitWrapper(blockchainType: blockchainType)?.evmKit.receiveAddress.eip55 ?? "-"
    }

    var feeData: FeeData? { .evm(evmFeeData: fee.0) }
    var canSend: Bool {
        guard ratio > 0 else { return false }
        guard let balance = ChildWalletBridge.shared.activeEvmKitWrapper(blockchainType: blockchainType)?.evmKit.accountState?.balance else {
            return true
        }
        return balance >= fee.0.totalFee(gasPrice: fee.1)
    }
    var rateCoins: [Coin] { coins }
    func cautions(baseToken: Token, currency _: Currency, rates _: [String: Decimal]) -> [CautionNew] {
        guard ratio > 0,
              let balance = ChildWalletBridge.shared.activeEvmKitWrapper(blockchainType: blockchainType)?.evmKit.accountState?.balance,
              balance < fee.0.totalFee(gasPrice: fee.1) else {
            return []
        }

        return [EvmSendHelper.caution(
            transactionError: AppError.ethereum(reason: .insufficientBalanceWithFee),
            feeToken: baseToken
        )]
    }
    func feeFields(baseToken: Token, currency: Currency, rates: [String: Decimal]) -> [SendField] {
        EvmSendHelper.feeFields(evmFeeData: fee.0, gasPrice: fee.1, feeToken: baseToken, currency: currency, feeTokenRate: rates[baseToken.coin.uid])
    }

    func sections(baseToken: Token, currency: Currency, rates: [String: Decimal]) -> [SendDataSection] {
        let allFields = fields + feeFields(baseToken: baseToken, currency: currency, rates: rates)
        guard !allFields.isEmpty else { return [] }
        return [.init(allFields)]
    }
}
