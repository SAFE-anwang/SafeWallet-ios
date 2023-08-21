import UIKit
import MarketKit
import HsToolKit
import CurrencyKit

class SendSafeLineLockFactory: BaseSendFactory {
    private let fiatService: FiatService
    private let amountCautionService: SendAmountCautionService
    private let feeFiatService: FiatService
    private let feeService: SendFeeService
    private let feeRateService: FeeRateService
    private let addressService: AddressService
    private let timeLockService: TimeLockService?
    private let adapterService: SendSafeLineLockAdapterService
    private let customFeeRateProvider: ICustomRangedFeeRateProvider?
    private let logger: Logger
    private let token: Token

    init(fiatService: FiatService, amountCautionService: SendAmountCautionService, addressService: AddressService, feeFiatService: FiatService, feeService: SendFeeService, feeRateService: FeeRateService, timeLockService: TimeLockService?, adapterService: SendSafeLineLockAdapterService, customFeeRateProvider: ICustomRangedFeeRateProvider?, logger: Logger, token: Token) {
        self.fiatService = fiatService
        self.amountCautionService = amountCautionService
        self.feeFiatService = feeFiatService
        self.feeService = feeService
        self.feeRateService = feeRateService
        self.addressService = addressService
        self.timeLockService = timeLockService
        self.adapterService = adapterService
        self.customFeeRateProvider = customFeeRateProvider
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
        viewItems.append(SendConfirmationFeeViewItem(coinValue: feeCoinValue, currencyValue: feeCurrencyValue))

        if (timeLockService?.lockTime ?? .none) != TimeLockService.Item.none {
            viewItems.append(SendConfirmationLockUntilViewItem(lockValue: timeLockService?.lockTime.title ?? "n/a".localized))
        }

        return viewItems
    }
    
    func getTimeLockService() -> TimeLockService? {
        timeLockService
    }

}

extension SendSafeLineLockFactory: ISendConfirmationFactory {

    func confirmationViewController() throws -> UIViewController {
        let items = try items()

        let service = SendConfirmationService(sendService: adapterService, logger: logger, token: token, items: items)
        let contactLabelService = ContactLabelService(contactManager: App.shared.contactManager, blockchainType: token.blockchainType)
        let viewModel = SendConfirmationViewModel(service: service, contactLabelService: contactLabelService)
        let viewController = SendConfirmationViewController(viewModel: viewModel)

        return viewController
    }

}

extension SendSafeLineLockFactory: ISendFeeSettingsFactory {
        
    func feeSettingsViewController() throws -> UIViewController {
        var dataSources: [ISendSettingsDataSource] = []

        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeCautionViewModel = SendFeeWarningViewModel(service: feeRateService)
        let amountCautionViewModel = SendFeeSettingsAmountCautionViewModel(service: amountCautionService, feeToken: token)
        let feeRateViewModel = FeeRateViewModel(service: feeRateService, feeCautionViewModel: feeCautionViewModel, amountCautionViewModel: amountCautionViewModel)
        if token.blockchainType == .unsupported(uid: safeCoinUid) {
            dataSources.append(FeeRateDataSource(feeViewModel: feeViewModel, feeRateViewModel: feeRateViewModel))
        }

        let inputOutputOrderViewModel = InputOutputOrderViewModel(service: adapterService.inputOutputOrderService)
        dataSources.append(InputOutputOrderDataSource(viewModel: inputOutputOrderViewModel))

        if let timeLockService = timeLockService {
            let timeLockViewModel = TimeLockViewModel(service: timeLockService)
            dataSources.append(TimeLockDataSource(viewModel: timeLockViewModel))
        }

        let viewController = SendSettingsViewController(dataSources: dataSources)

        return viewController
    }

}
