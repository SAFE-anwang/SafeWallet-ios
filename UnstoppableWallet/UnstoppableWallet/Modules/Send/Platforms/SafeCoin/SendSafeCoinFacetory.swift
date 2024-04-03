import HsToolKit
import MarketKit
import SwiftUI
import UIKit

class SendSafeCoinFactory: BaseSendFactory {
    private let fiatService: FiatService
    private let amountCautionService: SendAmountCautionService
    private let feeFiatService: FiatService
    private let feeService: SendFeeService
    private let feeRateService: FeeRateService
    private let addressService: AddressService
    private let timeLockService: TimeLockService?
    private let memoService: SendMemoInputService
    private let adapterService: SendSafeCoinAdapterService
    private let logger: Logger
    private let token: Token
    
    init(fiatService: FiatService, amountCautionService: SendAmountCautionService, addressService: AddressService, memoService: SendMemoInputService, feeFiatService: FiatService, feeService: SendFeeService, feeRateService: FeeRateService, timeLockService: TimeLockService?, adapterService: SendSafeCoinAdapterService, logger: Logger, token: Token) {
        self.fiatService = fiatService
        self.amountCautionService = amountCautionService
        self.feeFiatService = feeFiatService
        self.feeService = feeService
        self.feeRateService = feeRateService
        self.addressService = addressService
        self.timeLockService = timeLockService
        self.memoService = memoService
        self.adapterService = adapterService
        self.logger = logger
        self.token = token
    }

    private func items() throws -> [ISendConfirmationViewItemNew] {
        var viewItems = [ISendConfirmationViewItemNew]()

        guard let address = addressService.state.address else {
            throw ConfirmationError.noAddress
        }

        let (coinValue, currencyValue) = try values(fiatService: fiatService)
        let (feeCoinValue, feeCurrencyValue) = try values(fiatService: feeFiatService)

        viewItems.append(SendConfirmationAmountViewItem(coinValue: coinValue, currencyValue: currencyValue, receiver: address))
        
        if memoService.isAvailable, let memo = memoService.memo, !memo.isEmpty {
            viewItems.append(SendConfirmationMemoViewItem(memo: memo))
        }

        viewItems.append(SendConfirmationFeeViewItem(coinValue: feeCoinValue, currencyValue: feeCurrencyValue))
        
        if !App.shared.btcBlockchainManager.transactionRbfEnabled(blockchainType: token.blockchainType) {
            viewItems.append(SendConfirmationDisabledRbfViewItem())
        }

        if (timeLockService?.lockTime ?? .none) != TimeLockService.Item.none {
            viewItems.append(SendConfirmationLockUntilViewItem(lockValue: timeLockService?.lockTime.title ?? "n/a".localized))
        }

        return viewItems
    }
    
    func getTimeLockService() -> TimeLockService? {
        timeLockService
    }

}

extension SendSafeCoinFactory: ISendConfirmationFactory {

    func confirmationViewController() throws -> UIViewController {
        let items = try items()

        let service = SendConfirmationService(sendService: adapterService, logger: logger, token: token, items: items)
        let contactLabelService = ContactLabelService(contactManager: App.shared.contactManager, blockchainType: token.blockchainType)
        let viewModel = SendConfirmationViewModel(service: service, contactLabelService: contactLabelService)
        let viewController = SendConfirmationViewController(viewModel: viewModel)

        return viewController
    }

}

extension SendSafeCoinFactory: ISendFeeSettingsFactory {
        
    
    func feeSettingsViewController() throws -> UIViewController {
        var dataSources: [ISendSettingsDataSource] = []

        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeCautionViewModel = SendFeeCautionViewModel(service: feeRateService)
        let amountCautionViewModel = SendFeeSettingsAmountCautionViewModel(service: amountCautionService, feeToken: token)
        let feeRateViewModel = FeeRateViewModel(service: feeRateService, feeCautionViewModel: feeCautionViewModel, amountCautionViewModel: amountCautionViewModel)
        if token.blockchainType == .safe {
            dataSources.append(FeeRateDataSource(feeViewModel: feeViewModel, feeRateViewModel: feeRateViewModel))
        }

        let inputOutputOrderViewModel = InputOutputOrderViewModel(service: adapterService.inputOutputOrderService)
        dataSources.append(InputOutputOrderDataSource(viewModel: inputOutputOrderViewModel))

        let rbfViewModel = RbfViewModel(service: adapterService.rbfService)
        dataSources.append(RbfDataSource(viewModel: rbfViewModel))

        if let timeLockService {
            let timeLockViewModel = TimeLockViewModel(service: timeLockService)
            dataSources.append(TimeLockDataSource(viewModel: timeLockViewModel))
        }

        let viewController = SendSettingsViewController(dataSources: dataSources)

        return viewController
    }

}

