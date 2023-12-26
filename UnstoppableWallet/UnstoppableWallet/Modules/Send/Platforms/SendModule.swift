import UIKit
import ThemeKit
import MarketKit
import StorageKit
import RxCocoa

protocol ITitledCautionViewModel {
    var cautionDriver: Driver<TitledCaution?> { get }
}

class SendModule {

    static func controller(wallet: Wallet, mode: SendBaseService.Mode = .send) -> UIViewController? {
        guard let adapter = App.shared.adapterManager.adapter(for: wallet) else {
            return nil
        }
        // 启用lockTime功能
        App.shared.localStorage.lockTimeEnabled = true
        
        let token = wallet.token

        switch adapter {
        case let adapter as ISendSafeCoinAdapter:
            return SendModule.viewController(token: token, mode: mode, adapter: adapter)
        case let adapter as ISendBitcoinAdapter:
            return SendModule.viewController(token: token, mode: mode, adapter: adapter)
        case let adapter as ISendBinanceAdapter:
            return SendModule.viewController(token: token, mode: mode, adapter: adapter)
        case let adapter as ISendZcashAdapter:
            return SendModule.viewController(token: token, mode: mode, adapter: adapter)
        case let adapter as ISendEthereumAdapter:
            return SendEvmModule.viewController(token: token, mode: mode, adapter: adapter)
        case let adapter as ISendTronAdapter:
            return SendTronModule.viewController(token: token, mode: mode, adapter: adapter)
        default: return nil
        }
    }

    private static func viewController(token: Token, mode: SendBaseService.Mode, adapter: ISendBitcoinAdapter) -> UIViewController? {
        guard let feeRateProvider = App.shared.feeRateProviderFactory.provider(blockchainType: token.blockchainType) else {
            return nil
        }

        let switchService = AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default)
        let coinService = CoinService(token: token, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let fiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)

        // Amount
        let amountInputService = SendBitcoinAmountInputService(token: token)
        let amountCautionService = SendAmountCautionService(amountInputService: amountInputService)

        // Address
        let bitcoinParserItem = BitcoinAddressParserItem(parserType: .adapter(adapter))
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: bitcoinParserItem, coinCode: token.coin.code, token: token)
        let addressParserChain = AddressParserChain()
                .append(handler: bitcoinParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: bitcoinParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType)
        let addressService = AddressService(mode: .parsers(addressUriParser, addressParserChain), marketKit: App.shared.marketKit, contactBookManager: App.shared.contactManager, blockchainType: token.blockchainType)

        // Fee
        let feeRateService = FeeRateService(provider: feeRateProvider)
        let feeFiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let feeService = SendFeeService(fiatService: feeFiatService, feeToken: token)
        let inputOutputOrderService = InputOutputOrderService(blockchainType: adapter.blockchainType, blockchainManager: App.shared.btcBlockchainManager, itemsList: TransactionDataSortMode.allCases)

        // TimeLock
        var timeLockService: TimeLockService?
        var timeLockErrorService: SendTimeLockErrorService?

        if App.shared.localStorage.lockTimeEnabled, adapter.blockchainType == .bitcoin || adapter.blockchainType == .bitcoinCash || adapter.blockchainType == .dash || adapter.blockchainType == .litecoin, adapter.blockchainType == .dogecoin {
            let timeLockServiceInstance = TimeLockService()
            timeLockService = timeLockServiceInstance
            timeLockErrorService = SendTimeLockErrorService(timeLockService: timeLockServiceInstance, addressService: addressService, adapter: adapter)
        }

        let bitcoinAdapterService = SendBitcoinAdapterService(
                feeRateService: feeRateService,
                amountInputService: amountInputService,
                addressService: addressService,
                inputOutputOrderService: inputOutputOrderService,
                timeLockService: timeLockService,
                btcBlockchainManager: App.shared.btcBlockchainManager,
                adapter: adapter
        )
        let service = SendBitcoinService(
                amountService: amountInputService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                adapterService: bitcoinAdapterService,
                feeRateService: feeRateService,
                timeLockErrorService: timeLockErrorService,
                reachabilityManager: App.shared.reachabilityManager,
                token: token,
                mode: mode
        )

        //Add dependencies
        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        amountInputService.availableBalanceService = bitcoinAdapterService
        amountCautionService.availableBalanceService = bitcoinAdapterService
        amountCautionService.sendAmountBoundsService = bitcoinAdapterService

        addressService.customErrorService = timeLockErrorService

        feeService.feeValueService = bitcoinAdapterService

        // ViewModels
        let viewModel = SendViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: bitcoinAdapterService, coinService: coinService, switchService: switchService)
        let amountInputViewModel = AmountInputViewModel(
                service: amountInputService,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountInputViewModel

        let amountCautionViewModel = SendAmountCautionViewModel(
                service: amountCautionService,
                switchService: switchService,
                coinService: coinService
        )
        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        // Fee
        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeCautionViewModel = SendFeeCautionViewModel(service: feeRateService)

        let sendFactory = SendBitcoinFactory(
                fiatService: fiatService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                feeFiatService: feeFiatService,
                feeService: feeService,
                feeRateService: feeRateService,
                timeLockService: timeLockService,
                adapterService: bitcoinAdapterService,
                logger: App.shared.logger,
                token: token
        )

        let viewController = SendBitcoinViewController(
                confirmationFactory: sendFactory,
                feeSettingsFactory: sendFactory,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountInputViewModel: amountInputViewModel,
                amountCautionViewModel: amountCautionViewModel,
                recipientViewModel: recipientViewModel,
                feeViewModel: feeViewModel,
                feeCautionViewModel: feeCautionViewModel
        )

        return viewController
    }

    private static func viewController(token: Token, mode: SendBaseService.Mode, adapter: ISendBinanceAdapter) -> UIViewController? {
        let feeToken = App.shared.feeCoinProvider.feeToken(token: token) ?? token

        let switchService = AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default)
        let coinService = CoinService(token: token, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let fiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)

        // Amount
        let amountInputService = SendBitcoinAmountInputService(token: token)
        let amountCautionService = SendAmountCautionService(amountInputService: amountInputService)

        // Address
        let binanceParserItem = BinanceAddressParserItem(parserType: .adapter(adapter))
        let addressParserChain = AddressParserChain()
                .append(handler: binanceParserItem)

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType)
        let addressService = AddressService(mode: .parsers(addressUriParser, addressParserChain), marketKit: App.shared.marketKit, contactBookManager: App.shared.contactManager, blockchainType: token.blockchainType)

        let memoService = SendMemoInputService(maxSymbols: 120)

        // Fee
        let feeFiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let feeService = SendFeeService(fiatService: feeFiatService, feeToken: feeToken)

        let service = SendBinanceService(
                amountService: amountInputService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                memoService: memoService,
                adapter: adapter,
                reachabilityManager: App.shared.reachabilityManager,
                token: token,
                mode: mode
        )

        //Add dependencies
        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        amountInputService.availableBalanceService = service
        amountCautionService.availableBalanceService = service

        feeService.feeValueService = service

        // ViewModels
        let viewModel = SendViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)
        let amountInputViewModel = AmountInputViewModel(
                service: amountInputService,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountInputViewModel

        let amountCautionViewModel = SendAmountCautionViewModel(
                service: amountCautionService,
                switchService: switchService,
                coinService: coinService
        )
        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)
        let memoViewModel = SendMemoInputViewModel(service: memoService)

        // Fee
        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeWarningViewModel = SendBinanceFeeWarningViewModel(adapter: adapter, coinCode: token.coin.code, feeToken: feeToken)

        // Confirmation and Settings
        let sendFactory = SendBinanceFactory(
                service: service,
                fiatService: fiatService,
                addressService: addressService,
                memoService: memoService,
                feeFiatService: feeFiatService,
                logger: App.shared.logger,
                token: token
        )

        let viewController = SendBinanceViewController(
                confirmationFactory: sendFactory,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountInputViewModel: amountInputViewModel,
                amountCautionViewModel: amountCautionViewModel,
                recipientViewModel: recipientViewModel,
                memoViewModel: memoViewModel,
                feeViewModel: feeViewModel,
                feeWarningViewModel: feeWarningViewModel
        )

        return viewController
    }

    private static func viewController(token: Token, mode: SendBaseService.Mode, adapter: ISendZcashAdapter) -> UIViewController? {
        let switchService = AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default)
        let coinService = CoinService(token: token, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let fiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)

        // Amount
        let amountInputService = SendBitcoinAmountInputService(token: token)
        let amountCautionService = SendAmountCautionService(amountInputService: amountInputService)

        // Address
        let zcashParserItem = ZcashAddressParserItem(parserType: .adapter(adapter))
        let addressParserChain = AddressParserChain()
                .append(handler: zcashParserItem)

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType)
        let addressService = AddressService(mode: .parsers(addressUriParser, addressParserChain), marketKit: App.shared.marketKit, contactBookManager: App.shared.contactManager, blockchainType: token.blockchainType)

        let memoService = SendMemoInputService(maxSymbols: 120)

        // Fee
        let feeFiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let feeService = SendFeeService(fiatService: feeFiatService, feeToken: token)

        let service = SendZcashService(
                amountService: amountInputService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                memoService: memoService,
                adapter: adapter,
                reachabilityManager: App.shared.reachabilityManager,
                token: token,
                mode: mode
        )

        //Add dependencies
        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        amountInputService.availableBalanceService = service
        amountCautionService.availableBalanceService = service

        memoService.availableService = service
        feeService.feeValueService = service

        // ViewModels
        let viewModel = SendViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)
        let amountInputViewModel = AmountInputViewModel(
                service: amountInputService,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountInputViewModel

        let amountCautionViewModel = SendAmountCautionViewModel(
                service: amountCautionService,
                switchService: switchService,
                coinService: coinService
        )
        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)
        let memoViewModel = SendMemoInputViewModel(service: memoService)

        // Fee
        let feeViewModel = SendFeeViewModel(service: feeService)

        // Confirmation and Settings
        let sendFactory = SendZcashFactory(
                service: service,
                fiatService: fiatService,
                addressService: addressService,
                memoService: memoService,
                feeFiatService: feeFiatService,
                logger: App.shared.logger,
                token: token
        )

        let viewController = SendZcashViewController(
                confirmationFactory: sendFactory,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountInputViewModel: amountInputViewModel,
                amountCautionViewModel: amountCautionViewModel,
                recipientViewModel: recipientViewModel,
                memoViewModel: memoViewModel,
                feeViewModel: feeViewModel
        )

        return viewController
    }
    
    static func viewController(token: Token, mode: SendBaseService.Mode, adapter: ISendSafeCoinAdapter) -> UIViewController? {
        guard let feeRateProvider = App.shared.feeRateProviderFactory.provider(blockchainType: token.blockchainType) else {
            return nil
        }

        let switchService = AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default)
        let coinService = CoinService(token: token, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let fiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)

        // Amount
        let amountInputService = SendBitcoinAmountInputService(token: token)
        let amountCautionService = SendAmountCautionService(amountInputService: amountInputService)

        // Address
        let bitcoinParserItem = SafeCoinAddressParserItem(adapter: adapter)
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: bitcoinParserItem, coinCode: token.coin.code, token: token)
        let addressParserChain = AddressParserChain()
                .append(handler: bitcoinParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: bitcoinParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType)
        let addressService = AddressService(mode: .parsers(addressUriParser, addressParserChain), marketKit: App.shared.marketKit, contactBookManager: App.shared.contactManager, blockchainType: token.blockchainType)

        // Fee
        let feeRateService = FeeRateService(provider: feeRateProvider)
        let feeFiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let feeService = SendFeeService(fiatService: feeFiatService, feeToken: token)
        let inputOutputOrderService = InputOutputOrderService(blockchainType: adapter.blockchainType, blockchainManager: App.shared.btcBlockchainManager, itemsList: TransactionDataSortMode.allCases)

        // TimeLock
        var timeLockService: TimeLockService?
        var timeLockErrorService: SafeSendTimeLockErrorService?

        if App.shared.localStorage.lockTimeEnabled, adapter.blockchainType == .safe {
            let timeLockServiceInstance = TimeLockService()
            timeLockService = timeLockServiceInstance
            timeLockErrorService = SafeSendTimeLockErrorService(timeLockService: timeLockServiceInstance, addressService: addressService, adapter: adapter)
        }

        let bitcoinAdapterService = SendSafeCoinAdapterService(
                feeRateService: feeRateService,
                amountInputService: amountInputService,
                addressService: addressService,
                inputOutputOrderService: inputOutputOrderService,
                timeLockService: timeLockService,
                btcBlockchainManager: App.shared.btcBlockchainManager,
                adapter: adapter
        )
        let service = SendSafeCoinService(
                amountService: amountInputService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                adapterService: bitcoinAdapterService,
                feeRateService: feeRateService,
                timeLockErrorService: timeLockErrorService,
                reachabilityManager: App.shared.reachabilityManager,
                token: token,
                mode: mode
        )

        //Add dependencies
        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        amountInputService.availableBalanceService = bitcoinAdapterService
        amountCautionService.availableBalanceService = bitcoinAdapterService
        amountCautionService.sendAmountBoundsService = bitcoinAdapterService

        addressService.customErrorService = timeLockErrorService

        feeService.feeValueService = bitcoinAdapterService

        // ViewModels
        let viewModel = SendViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: bitcoinAdapterService, coinService: coinService, switchService: switchService)
        let amountInputViewModel = AmountInputViewModel(
                service: amountInputService,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountInputViewModel

        let amountCautionViewModel = SendAmountCautionViewModel(
                service: amountCautionService,
                switchService: switchService,
                coinService: coinService
        )
        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        // Fee
        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeWarningViewModel = SendFeeCautionViewModel(service: feeRateService)

        // Confirmation and Settings
        let sendFactory = SendSafeCoinFactory(
                fiatService: fiatService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                feeFiatService: feeFiatService,
                feeService: feeService,
                feeRateService: feeRateService,
                timeLockService: timeLockService,
                adapterService: bitcoinAdapterService,
                logger: App.shared.logger,
                token: token
        )

        let viewController = SendBitcoinViewController(
                confirmationFactory: sendFactory,
                feeSettingsFactory: sendFactory,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountInputViewModel: amountInputViewModel,
                amountCautionViewModel: amountCautionViewModel,
                recipientViewModel: recipientViewModel,
                feeViewModel: feeViewModel,
                feeCautionViewModel: feeWarningViewModel
        )

        return viewController
    }
    
    // 跨链：sfe => wsafe
    static func wsafeViewController(token: Token, mode: SendBaseService.Mode, adapter: ISendSafeCoinAdapter, ethAdapter: ISendEthereumAdapter, data: Safe4Data) -> UIViewController? {
        guard let feeRateProvider = App.shared.feeRateProviderFactory.provider(blockchainType: token.blockchainType) else {
            return nil
        }

        let switchService = AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default)
        let coinService = CoinService(token: token, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let fiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)

        // Amount
        let amountInputService = SendBitcoinAmountInputService(token: token)
        let amountCautionService = SendAmountCautionService(amountInputService: amountInputService)

        // Address
        let bitcoinParserItem = SafeCoinAddressParserItem(adapter: adapter)
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: bitcoinParserItem, coinCode: token.coin.code, token: token)
        let addressParserChain = AddressParserChain()
                .append(handler: bitcoinParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: bitcoinParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType)
        let addressService = AddressService(mode: .parsers(addressUriParser, addressParserChain), marketKit: App.shared.marketKit, contactBookManager: App.shared.contactManager, blockchainType: token.blockchainType, initialAddress: data.reciverAddress)

        // Fee
        let feeRateService = FeeRateService(provider: feeRateProvider)
        let feeFiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let feeService = SendFeeService(fiatService: feeFiatService, feeToken: token)
        let inputOutputOrderService = InputOutputOrderService(blockchainType: adapter.blockchainType, blockchainManager: App.shared.btcBlockchainManager, itemsList: TransactionDataSortMode.allCases)
/*
        // TimeLock
        var timeLockService: TimeLockService?
        var timeLockErrorService: SafeSendTimeLockErrorService?

        if App.shared.localStorage.lockTimeEnabled, adapter.blockchainType == .unsupported(uid: safeCoinUid) {
            let timeLockServiceInstance = TimeLockService()
            timeLockService = timeLockServiceInstance
            timeLockErrorService = SafeSendTimeLockErrorService(timeLockService: timeLockServiceInstance, addressService: addressService, adapter: adapter)
        }
*/
        let adapterService = SendSafe2wsafeAdapterService(
                feeRateService: feeRateService,
                amountInputService: amountInputService,
                addressService: addressService,
                inputOutputOrderService: inputOutputOrderService,
                timeLockService: nil,//timeLockService,
                btcBlockchainManager: App.shared.btcBlockchainManager,
                adapter: adapter,
                ethAdapter: ethAdapter,
                contractAddress: data.contractAddress
        )
        
        let service = SendSafe2wsafeService(
                amountService: amountInputService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                adapterService: adapterService,
                feeRateService: feeRateService,
                timeLockErrorService: nil,//timeLockErrorService,
                reachabilityManager: App.shared.reachabilityManager,
                token: token,
                mode: mode
        )

        //Add dependencies
        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        amountInputService.availableBalanceService = adapterService
        amountCautionService.availableBalanceService = adapterService
        amountCautionService.sendAmountBoundsService = adapterService

        addressService.customErrorService = nil //timeLockErrorService

        feeService.feeValueService = adapterService

        // ViewModels
        let viewModel = SendViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: adapterService, coinService: coinService, switchService: switchService)
        let amountInputViewModel = AmountInputViewModel(
                service: amountInputService,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountInputViewModel

        let amountCautionViewModel = SendAmountCautionViewModel(
                service: amountCautionService,
                switchService: switchService,
                coinService: coinService
        )
        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        // Fee
        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeWarningViewModel = SendFeeCautionViewModel(service: feeRateService)

        // Confirmation and Settings

        let sendFactory = SendSafe2wsafeFactory(
                fiatService: fiatService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                feeFiatService: feeFiatService,
                feeService: feeService,
                feeRateService: feeRateService,
                timeLockService: nil,//timeLockService,
                adapterService: adapterService,
                logger: App.shared.logger,
                token: token,
                contractAddress: data.contractAddress
        )

        let viewController = SendSafe2wsafeViewController(
                confirmationFactory: sendFactory,
                feeSettingsFactory: sendFactory,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountInputViewModel: amountInputViewModel,
                amountCautionViewModel: amountCautionViewModel,
                recipientViewModel: recipientViewModel,
                feeViewModel: feeViewModel,
                feeWarningViewModel: feeWarningViewModel
        )
        var title = ""
        if data.isETH {
            title = "SAFE => SAFE ERC20"
        } else if data.isMatic {
            title = "SAFE => SAFE MATIC"
        }else {
            title = "SAFE => SAFE BEP20"
        }
        
        viewController.title = title
        return ThemeNavigationController(rootViewController: viewController)
    }
    
    static func lineLockViewController(token: Token, mode: SendBaseService.Mode, adapter: ISendSafeCoinAdapter, reciverAddress: Address?) -> UIViewController? {
        guard let feeRateProvider = App.shared.feeRateProviderFactory.provider(blockchainType: token.blockchainType) else {
            return nil
        }

        let switchService = AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default)
        let coinService = CoinService(token: token, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let fiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)

        // Amount
        let amountInputService = SendBitcoinAmountInputService(token: token)
        let amountCautionService = SendAmountCautionService(amountInputService: amountInputService)

        // Address
        let bitcoinParserItem = SafeCoinAddressParserItem(adapter: adapter)
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: bitcoinParserItem, coinCode: token.coin.code, token: token)
        let addressParserChain = AddressParserChain()
                .append(handler: bitcoinParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: bitcoinParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType)
        let addressService = AddressService(mode: .parsers(addressUriParser, addressParserChain), marketKit: App.shared.marketKit, contactBookManager: App.shared.contactManager, blockchainType: token.blockchainType, initialAddress: reciverAddress)

        // Fee
        let feeRateService = FeeRateService(provider: feeRateProvider)
        let feeFiatService = FiatService(switchService: switchService, currencyKit: App.shared.currencyKit, marketKit: App.shared.marketKit)
        let feeService = SendFeeService(fiatService: feeFiatService, feeToken: token)
        let inputOutputOrderService = InputOutputOrderService(blockchainType: adapter.blockchainType, blockchainManager: App.shared.btcBlockchainManager, itemsList: TransactionDataSortMode.allCases)

        // TimeLock
//        var timeLockService: TimeLockService?
//        var timeLockErrorService: SendTimeLockErrorService?
//
//        if App.shared.localStorage.lockTimeEnabled, adapter.blockchainType == .bitcoin || adapter.blockchainType == .bitcoinCash || adapter.blockchainType == .dash || adapter.blockchainType == .litecoin {
//            let timeLockServiceInstance = TimeLockService()
//            timeLockService = timeLockServiceInstance
//            timeLockErrorService = SendTimeLockErrorService(timeLockService: timeLockServiceInstance, addressService: addressService, adapter: adapter)
//        }
        
        let lineLockInputService = LineLockInputService(service: amountInputService, fiatService: fiatService)
        
        let contractAddress = Address(raw: "Xh7bkG6cAt1taBzNGKUCJRUowcgZ4qS5TY")
        
        let bitcoinAdapterService = SendSafeLineLockAdapterService(
                feeRateService: feeRateService,
                amountInputService: amountInputService,
                addressService: addressService,
                inputOutputOrderService: inputOutputOrderService,
                timeLockService: nil,//timeLockService,
                btcBlockchainManager: App.shared.btcBlockchainManager,
                adapter: adapter,
                lineLockInputService: lineLockInputService
        )
        let service = SendSafeLineLockService(
                amountService: amountInputService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                adapterService: bitcoinAdapterService,
                feeRateService: feeRateService,
                timeLockErrorService: nil,// timeLockErrorService,
                reachabilityManager: App.shared.reachabilityManager,
                token: token,
                mode: mode,
                lineLockInputService: lineLockInputService
        )

        //Add dependencies
        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        amountInputService.availableBalanceService = bitcoinAdapterService
        amountCautionService.availableBalanceService = bitcoinAdapterService
        amountCautionService.sendAmountBoundsService = bitcoinAdapterService

        addressService.customErrorService = nil //timeLockErrorService

        feeService.feeValueService = bitcoinAdapterService

        // ViewModels
        let viewModel = SendViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: bitcoinAdapterService, coinService: coinService, switchService: switchService)
        let amountInputViewModel = AmountInputViewModel(
                service: amountInputService,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountInputViewModel

        let amountCautionViewModel = SendAmountCautionViewModel(
                service: amountCautionService,
                switchService: switchService,
                coinService: coinService
        )
        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        // Fee
        let feeViewModel = SendFeeViewModel(service: feeService)
        let feeWarningViewModel = SendFeeCautionViewModel(service: feeRateService)

        // Confirmation and Settings

        let sendFactory = SendSafeLineLockFactory(
                fiatService: fiatService,
                amountCautionService: amountCautionService,
                addressService: addressService,
                feeFiatService: feeFiatService,
                feeService: feeService,
                feeRateService: feeRateService,
                timeLockService: nil,//timeLockService,
                adapterService: bitcoinAdapterService,
                logger: App.shared.logger,
                token: token
        )
        
        let lineLockInputViewModel = LineLockInputViewModel(
            service: amountInputService,
            decimalParser: AmountDecimalParser(),
            lineLockInputService: lineLockInputService
        )
        
        let viewController = SendSafeLineLockViewController(
                confirmationFactory: sendFactory,
                feeSettingsFactory: sendFactory,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountInputViewModel: amountInputViewModel,
                amountCautionViewModel: amountCautionViewModel,
                recipientViewModel: recipientViewModel,
                feeViewModel: feeViewModel,
                feeWarningViewModel: feeWarningViewModel,
                lineLockInputViewModel: lineLockInputViewModel
        )

        return ThemeNavigationController(rootViewController: viewController)
    }
}
