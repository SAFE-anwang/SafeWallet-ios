import BitcoinCore
import EvmKit
import Foundation
import MarketKit
import StellarKit
import TonSwift
import TronKit
import ZcashLightClientKit

enum SendData {
    case evm(blockchainType: BlockchainType, transactionData: TransactionData)
    case bitcoin(token: Token, params: SendParameters)
    case zcash(amount: Decimal, recipient: Recipient, memo: String?)
    case zcashShield(amount: Decimal, recipient: Recipient?, memo: String?)
    case tron(token: Token, contract: TronKit.Contract)
    case ton(token: Token, amount: Decimal, address: FriendlyAddress, memo: String?)
    case stellar(data: StellarSendData, token: Token, memo: String?)
    case swap(tokenIn: Token, tokenOut: Token, amountIn: Decimal, provider: IMultiSwapProvider)
    case walletConnect(request: WalletConnectRequest)
    case tonConnect(request: TonConnectSendTransactionRequest)
    case monero(token: Token, amount: MoneroSendAmount, address: String, memo: String?)
    case evmSafe4TimeLock(blockchainType: BlockchainType, transactionData: TransactionData, timeLock: TimeLock)
    case crossChain(baseWallet: Wallet, transactionData: TransactionData)
    case liquidityAdd(token0: Token, token1: Token, amount0: Decimal, amount1: Decimal, provider: ILiquidityAddProvider, v3TickType: LiquidityTickType?)
}

enum StellarSendData {
    case payment(asset: Asset, amount: Decimal, accountId: String)
    case changeTrust(asset: Asset, limit: Decimal)
}
