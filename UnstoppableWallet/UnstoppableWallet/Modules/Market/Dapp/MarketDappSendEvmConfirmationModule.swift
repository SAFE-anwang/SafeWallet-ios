import EvmKit
import Foundation
import MarketKit
import UIKit

enum MarketDappSendEvmConfirmationModule {
    static func viewController(
        evmKitWrapper: EvmKitWrapper,
        sendData: SendEvmData,
        onSendSuccess: @escaping (Data) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) -> UIViewController? {
        let evmKit = evmKitWrapper.evmKit

        guard let coinServiceFactory = EvmCoinServiceFactory(
            blockchainType: evmKitWrapper.blockchainType,
            marketKit: Core.shared.marketKit,
            currencyManager: Core.shared.currencyManager,
            coinManager: Core.shared.coinManager
        ) else {
            return nil
        }

        let predefinedGasLimit: Int? = [.ethereum, .polygon, .binanceSmartChain].contains(evmKitWrapper.blockchainType) ? 100000 : nil

        guard let (settingsService, settingsViewModel) = EvmSendSettingsModule.instance(
            evmKit: evmKit,
            blockchainType: evmKitWrapper.blockchainType,
            sendData: sendData,
            coinServiceFactory: coinServiceFactory,
            predefinedGasLimit: predefinedGasLimit,
            gasLimitType: .common
        ) else {
            return nil
        }

        let service = SendEvmTransactionService(sendData: sendData, privateSendMode: .none, evmKitWrapper: evmKitWrapper, settingsService: settingsService, evmLabelManager: Core.shared.evmLabelManager)
        let contactLabelService = ContactLabelService(contactManager: Core.shared.contactManager, blockchainType: evmKitWrapper.blockchainType)
        let viewModel = SendEvmTransactionViewModel(service: service, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: Core.shared.evmLabelManager, contactLabelService: contactLabelService)

        return MarketDappSendEvmConfirmationViewController(
            mode: .send,
            transactionViewModel: viewModel,
            settingsViewModel: settingsViewModel,
            onSendSuccess: onSendSuccess,
            onSendFailed: onSendFailed
        )
    }
}

final class MarketDappSendEvmConfirmationViewController: SendEvmConfirmationViewController {
    private let onSendSuccess: (Data) -> Void
    private let onSendFailed: (String) -> Void
    private var finished = false

    init(
        mode: Mode,
        transactionViewModel: SendEvmTransactionViewModel,
        settingsViewModel: EvmSendSettingsViewModel,
        onSendSuccess: @escaping (Data) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) {
        self.onSendSuccess = onSendSuccess
        self.onSendFailed = onSendFailed
        super.init(mode: mode, transactionViewModel: transactionViewModel, settingsViewModel: settingsViewModel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func handleSendSuccess(transactionHash: Data) {
        if !finished {
            finished = true
            onSendSuccess(transactionHash)
        }
        super.handleSendSuccess(transactionHash: transactionHash)
    }

    override func handleSendFailed(error: String) {
        if !finished {
            finished = true
            onSendFailed(error)
        }
        super.handleSendFailed(error: error)
    }
}
