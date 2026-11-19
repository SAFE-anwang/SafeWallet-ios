import MarketKit

public enum SendHandlerFactory {
    private static var providers: [SendHandler.Type] = []
    private static var preSendProviders: [PreSendHandler.Type] = []

    public static func register(_ provider: SendHandler.Type) {
        providers.append(provider)
    }

    public static func register(_ provider: PreSendHandler.Type) {
        preSendProviders.append(provider)
    }

    public static func prepend(_ provider: SendHandler.Type) {
        providers.insert(provider, at: 0)
    }

    public static func prepend(_ provider: PreSendHandler.Type) {
        preSendProviders.insert(provider, at: 0)
    }

    // Backstop for every send screen: the entry points are gated in the UI, this catches the ones that are not.
    // It must run before the providers: PrivateSendHandlerProvider/CrossPayHandlerProvider commit an order with the
    // provider while building their handler, so a later nil would leave that order unpaid.
    static func handler(sendData: SendData) -> ISendHandler? {
        guard ChildWalletBridge.shared.supports(account: Core.shared.accountManager.activeAccount, sendData: sendData) else {
            return nil
        }
        if Core.shared.accountManager.activeAccount?.watchAccount == true {
            return nil
        }

        for provider in providers {
            if let handler = provider.instance(sendData: sendData) {
                return handler
            }
        }

        switch sendData {
        case let .openCryptoPay(payment, entry, inner):
            return OpenCryptoPaySendHandlerFactory.handler(payment: payment, entry: entry, inner: inner)
        case let .liquidityAdd(token0, token1, amount0, amount1, provider, v3TickType, manualAmountOutMode):
            return LiquidityAddSendHandler.instance(token0: token0, token1: token1, amount0: amount0, amount1: amount1, provider: provider, v3TickType: v3TickType, manualAmountOutMode: manualAmountOutMode)
        case let .liquidityRemove(request):
            return request.makeHandler()
        case let .evmSafe4TimeLock(blockchainType, transactionData, timeLock):
            return EvmSendHandler.instance(blockchainType: blockchainType, transactionData: transactionData, timeLock: timeLock)
        case let .crossChain(baseWallet, transactionData):
            return CrossChainSendHandler.instance(baseWallet: baseWallet, transactionData: transactionData)
        default:
            return nil
        }
    }

    public static func preSendHandler(wallet: Wallet, address: ResolvedAddress?) -> IPreSendHandler? {
        if wallet.account.watchAccount {
            return nil
        }

        guard ChildWalletBridge.shared.supports(account: wallet.account, token: wallet.token) else {
            return nil
        }
        for provider in preSendProviders {
            if let handler = provider.instance(wallet: wallet, address: address) {
                return handler
            }
        }

        return nil
    }
}

public extension SendHandlerFactory {
    static let unstoppableHandlers: [SendHandler.Type] = [
        PrivateSendHandlerProvider.self,
        CrossPayHandlerProvider.self,
        EvmSendHandler.self,
        EvmResendHandler.self,
        BitcoinResendHandler.self,
        BitcoinSendHandler.self,
        ZcashSendHandler.self,
        ShieldSendHandler.self,
        MigrationSendHandler.self,
        TronSendHandler.self,
        ThorChainSendHandler.self,
        TonSendHandler.self,
        StellarSendHandler.self,
        SolanaSendHandler.self,
        XrpSendHandler.self,
        NearSendHandler.self,
        MoneroSendHandler.self,
        ZanoSendHandler.self,
        MultiSwapSendHandler.self,
        SplitSwapSendHandler.self,
        TonConnectSendHandler.self,
    ]

    static let unstoppablePreSendHandlers: [PreSendHandler.Type] = [
        EvmPreSendHandler.self,
        BitcoinPreSendHandler.self,
        ZcashPreSendHandler.self,
        TronPreSendHandler.self,
        ThorChainPreSendHandler.self,
        TonPreSendHandler.self,
        SolanaPreSendHandler.self,
        StellarPreSendHandler.self,
        XrpPreSendHandler.self,
        NearPreSendHandler.self,
        MoneroPreSendHandler.self,
        ZanoPreSendHandler.self,
    ]
}
