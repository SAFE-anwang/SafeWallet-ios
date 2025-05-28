import MarketKit
import ThemeKit
import UIKit

enum SendEvmModule {
    static func viewController(token: Token, mode: SendBaseService.Mode, adapter: ISendEthereumAdapter) -> UIViewController {
        let evmAddressParserItem = EvmAddressParser()
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: evmAddressParserItem, coinCode: token.coin.code, token: token)

        let addressParserChain = AddressParserChain()
            .append(handler: evmAddressParserItem)
            .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: evmAddressParserItem)
        {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType, tokenType: token.type)
        let addressService = AddressService(
            mode: .parsers(addressUriParser, addressParserChain),
            marketKit: App.shared.marketKit,
            contactBookManager: App.shared.contactManager,
            blockchainType: token.blockchainType
        )

        let service = SendEvmService(token: token, mode: mode, adapter: adapter, addressService: addressService)

        let switchService = AmountTypeSwitchService(userDefaultsStorage: App.shared.userDefaultsStorage)
        let fiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        let coinService = CoinService(token: token, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)
        let timeLockService: TimeLockService? = token.coin.uid == safe4CoinUid ? TimeLockService() : nil

        let viewModel = SendEvmViewModel(service: service, timeLockService: timeLockService)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)

        let amountViewModel = AmountInputViewModel(
            service: service,
            fiatService: fiatService,
            switchService: switchService,
            decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountViewModel

        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)
        let timeLockViewModel = timeLockService != nil ? TimeLockViewModel(service: timeLockService!) : nil

        let viewController = SendEvmViewController(
            evmKitWrapper: adapter.evmKitWrapper,
            viewModel: viewModel,
            availableBalanceViewModel: availableBalanceViewModel,
            amountViewModel: amountViewModel,
            recipientViewModel: recipientViewModel,
            timeLockViewModel: timeLockViewModel
        )

        return viewController
    }
         
    // 跨链： wsafe => safe
    static func wsafeViewController(token: Token, wsafeAdapter: ISendEthereumAdapter, crossChainInfo: SafeCrossChainInfo) -> UIViewController {
        let evmAddressParserItem = EvmAddressParser()
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: evmAddressParserItem, coinCode: token.coin.code, token: token)

        let addressParserChain = AddressParserChain()
                .append(handler: evmAddressParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: token.blockchainType),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: evmAddressParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType, tokenType: token.type)
        
        let addressService = AddressService(
                mode: .parsers(addressUriParser, addressParserChain),
                marketKit: App.shared.marketKit,
                contactBookManager: App.shared.contactManager,
                blockchainType: token.blockchainType,
                initialAddress: crossChainInfo.reciverAddress
        )

        let service = SendWsafeService(token: token, adapter: wsafeAdapter, addressService: addressService)

        let switchService = AmountTypeSwitchService(userDefaultsStorage: App.shared.userDefaultsStorage)
        let fiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        let coinService = CoinService(token: token, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        let viewModel = SendWsafeViewModel(service: service, isMatic: crossChainInfo.isMatic)
        viewModel.onEnterAddress(wsafeWallet: crossChainInfo.wsafeWallet, safeWallet: crossChainInfo.safeWallet, address: crossChainInfo.reciverAddress)

        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)

        let amountViewModel = AmountInputViewModel(
                service: service,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountViewModel

        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        let viewController = SendWSafeEvmViewController(
                evmKitWrapper: wsafeAdapter.evmKitWrapper,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountViewModel: amountViewModel,
                recipientViewModel: recipientViewModel
        )

        viewController.title = crossChainInfo.navTitle
        return ThemeNavigationController(rootViewController: viewController)
    }
    
//     跨链：safe => wsafe
    static func safe4ViewController(token: Token, wsafeChainType: WSafeChainType, safeAdapter: ISendEthereumAdapter, crossChainInfo: SafeCrossChainInfo) -> UIViewController {
        let evmAddressParserItem = EvmAddressParser()
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: evmAddressParserItem, coinCode: token.coin.code, token: token)

        let addressParserChain = AddressParserChain()
                .append(handler: evmAddressParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: token.blockchainType),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: evmAddressParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType, tokenType: token.type)
        
        let addressService = AddressService(
                mode: .parsers(addressUriParser, addressParserChain),
                marketKit: App.shared.marketKit,
                contactBookManager: App.shared.contactManager,
                blockchainType: token.blockchainType,
                initialAddress: crossChainInfo.reciverAddress
        )

        let service = SendSafe4ToWSafeService(token: token, wsafeChainType: wsafeChainType, adapter: safeAdapter, addressService: addressService)

        let switchService = AmountTypeSwitchService(userDefaultsStorage: App.shared.userDefaultsStorage)
        let fiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        let coinService = CoinService(token: token, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        let viewModel = SendSafe4ToWSafeViewModel(service: service, isMatic: crossChainInfo.isMatic)
        viewModel.onEnterAddress(wsafeWallet: crossChainInfo.wsafeWallet, safeWallet: crossChainInfo.safeWallet, address: crossChainInfo.reciverAddress)

        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)

        let amountViewModel = AmountInputViewModel(
                service: service,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountViewModel

        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        let viewController = SendSafe4ToWSafeEvmViewController(
                evmKitWrapper: safeAdapter.evmKitWrapper,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountViewModel: amountViewModel,
                recipientViewModel: recipientViewModel
        )

        viewController.title = crossChainInfo.navTitle
        return ThemeNavigationController(rootViewController: viewController)
    }
}
