import Eip20Kit
import EvmKit
import Foundation
import MarketKit
import SwiftUI

class EvmSendHandler: SendHandler {
    let baseToken: Token
    private let transactionData: TransactionData
    private let evmKitWrapper: EvmKitWrapper
    private let sendToken: Token
    private let balanceAdapter: IBalanceAdapter?
    private let decorator = EvmDecorator()
    private let evmFeeEstimator = EvmFeeEstimator()
    private let timeLock: TimeLock?

    init(baseToken: Token, transactionData: TransactionData, evmKitWrapper: EvmKitWrapper, sendToken: Token, balanceAdapter: IBalanceAdapter?, timeLock: TimeLock? = nil) {
        self.baseToken = baseToken
        self.transactionData = transactionData
        self.evmKitWrapper = evmKitWrapper
        self.timeLock = timeLock
        self.sendToken = sendToken
        self.balanceAdapter = balanceAdapter
    }

    override class func instance(sendData: SendData) -> ISendHandler? {
        guard case let .evm(blockchainType, transactionData, token) = sendData else { return nil }
        return instance(blockchainType: blockchainType, transactionData: transactionData, sendToken: token)
    }
}

extension EvmSendHandler: ISendHandler {
    var expirationDuration: Int? {
        10
    }

    var supportsFeeSettings: Bool {
        !isSrc20TimeLock
    }

    var supportsNonceSettings: Bool {
        !isSrc20TimeLock
    }

    func sendData(transactionSettings: TransactionSettings?) async throws -> ISendData {
        let gasPriceData = transactionSettings?.gasPriceData
        var evmFeeData: EvmFeeData?
        var transactionError: Error?
        var transactionData = transactionData

        if let gasPriceData {
            let evmBalance = evmKitWrapper.evmKit.accountState?.balance ?? 0

            do {
                // A token shortfall is answered locally: the node's revert for it has no stable
                // shape (a revert string on some RPCs, a bare -32003 on others), so the standard
                // insufficient caution is produced before estimation instead.
                if let balanceAdapter, case .synced = balanceAdapter.balanceState,
                   Self.isInsufficientEip20Balance(
                       decoration: evmKitWrapper.evmKit.decorate(transactionData: transactionData),
                       sendToken: sendToken,
                       availableBalance: balanceAdapter.balanceData.available
                   )
                {
                    throw AppError.ethereum(reason: .insufficientBalanceWithFee)
                }

                if transactionData.value > evmBalance {
                    throw AppError.ethereum(reason: .insufficientBalanceWithFee)
                } else if transactionData.input.isEmpty, transactionData.value == evmBalance {
                    let stubTransactionData = TransactionData(to: transactionData.to, value: 1, input: transactionData.input)
                    let stubFeeData = try await evmFeeEstimator.estimateFee(evmKitWrapper: evmKitWrapper, transactionData: stubTransactionData, gasPriceData: gasPriceData)
                    let totalFee = stubFeeData.totalFee(gasPrice: gasPriceData.userDefined)

                    evmFeeData = stubFeeData
                    let value = transactionData.value > totalFee ? transactionData.value - totalFee : 0
                    transactionData = TransactionData(to: transactionData.to, value: value, input: transactionData.input)

                    if transactionData.value == 0 {
                        throw AppError.ethereum(reason: .insufficientBalanceWithFee)
                    }
                } else {
                    let _evmFeeData = try await evmFeeEstimator.estimateFee(evmKitWrapper: evmKitWrapper, transactionData: transactionData, gasPriceData: gasPriceData)
                    let totalFee = _evmFeeData.totalFee(gasPrice: gasPriceData.userDefined)

                    evmFeeData = _evmFeeData

                    if evmBalance < totalFee {
                        throw AppError.ethereum(reason: .insufficientBalanceWithFee)
                    }
                }
            } catch {
                transactionError = error
            }
        }

        let transactionDecoration = evmKitWrapper.evmKit.decorate(transactionData: transactionData)
        let decoration = decorator.decorate(baseToken: baseToken, transactionData: transactionData, transactionDecoration: transactionDecoration, timeLock: timeLock)

        return EvmSendData(
            decoration: decoration,
            transactionData: transactionData,
            transactionError: transactionError,
            gasPrice: gasPriceData?.userDefined,
            evmFeeData: evmFeeData,
            nonce: transactionSettings?.nonce,
            timeLock: timeLock,
            feeToken: baseToken

        )
    }

    func send(data: ISendData) async throws {
        _ = try await sendCapturingRef(data: data)
    }
}

extension EvmSendHandler: ISendHandlerRefCapturing {
    // Same broadcast path as `send`, returning the on-chain tx hash.
    func sendCapturingRef(data: ISendData) async throws -> String {
        guard let data = data as? EvmSendData else {
            throw SendError.invalidData
        }

        guard let transactionData = data.transactionData else {
            throw SendError.noTransactionData
        }

        guard let gasPrice = data.gasPrice else {
            throw SendError.noGasPrice
        }

        guard let gasLimit = data.evmFeeData?.surchargedGasLimit else {
            throw SendError.noGasLimit
        }
        if let timeLock = data.timeLock {
            switch timeLock.token {
            case .native:
                let fullTransaction = try await evmKitWrapper.sendSafe4TimeLock(
                    transactionData: transactionData,
                    gasPrice: gasPrice,
                    gasLimit: gasLimit,
                    nonce: data.nonce,
                    timeLock: timeLock
                )
                return fullTransaction.transaction.hash.hs.hexString
            case .src20:
                return try await evmKitWrapper.sendSrc20TimeLock(
                    to: transactionData.to,
                    timeLock: timeLock
                )
            }
        }

        let fullTransaction = try await evmKitWrapper.send(
            transactionData: transactionData,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            privateSend: false,
            nonce: data.nonce
        )

        return fullTransaction.transaction.hash.hs.hexString
    }
}

private extension EvmSendHandler {
    var isSrc20TimeLock: Bool {
        guard let timeLock else {
            return false
        }

        if case .src20 = timeLock.token {
            return true
        }

        return false
    }
}

extension EvmSendHandler {
    enum SendError: Error {
        case invalidData
        case noGasPrice
        case noGasLimit
        case noTransactionData
    }
}

extension EvmSendHandler {
    static func instance(blockchainType: BlockchainType, transactionData: TransactionData, sendToken: Token? = nil, timeLock: TimeLock? = nil) -> EvmSendHandler? {
        guard let baseToken = try? Core.shared.coinManager.token(query: .init(blockchainType: blockchainType, tokenType: .native)) else {
            return nil
        }

        guard let evmKitWrapper = ChildWalletBridge.shared.activeEvmKitWrapper(blockchainType: blockchainType) else {
            return nil
        }

        let resolvedToken: Token
        if let sendToken {
            resolvedToken = sendToken
        } else if case let .src20(contract)? = timeLock?.token {
            guard let token = try? Core.shared.coinManager.token(query: .init(blockchainType: blockchainType, tokenType: .eip20(address: contract.hex))) else { return nil }
            resolvedToken = token
        } else {
            resolvedToken = baseToken
        }

        return EvmSendHandler(
            baseToken: baseToken,
            transactionData: transactionData,
            evmKitWrapper: evmKitWrapper,
            sendToken: resolvedToken,
            balanceAdapter: Core.shared.adapterManager.adapter(for: resolvedToken) as? IBalanceAdapter,
            timeLock: timeLock
        )
    }

    static func isInsufficientEip20Balance(decoration: TransactionDecoration?, sendToken: Token, availableBalance: Decimal?) -> Bool {
        guard case let .eip20(address) = sendToken.type,
              let tokenAddress = try? EvmKit.Address(hex: address),
              let transfer = decoration as? OutgoingEip20Decoration,
              transfer.contractAddress == tokenAddress,
              let availableBalance,
              let amount = Decimal(bigUInt: transfer.value, decimals: sendToken.decimals)
        else {
            return false
        }

        return amount > availableBalance
    }
}
