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

        let viewModel = SendEvmViewModel(service: service)
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)

        let amountViewModel = AmountInputViewModel(
            service: service,
            fiatService: fiatService,
            switchService: switchService,
            decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountViewModel

        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        let viewController = SendEvmViewController(
            evmKitWrapper: adapter.evmKitWrapper,
            viewModel: viewModel,
            availableBalanceViewModel: availableBalanceViewModel,
            amountViewModel: amountViewModel,
            recipientViewModel: recipientViewModel
        )

        return viewController
    }
    
    static func wsafeViewController(wallet: Wallet, data: Safe4Data) -> UIViewController? {
        guard let adapter = App.shared.adapterManager.adapter(for: wallet) else {
            return nil
        }

        switch adapter {
        case let adapter as ISendEthereumAdapter:
            return SendEvmModule.wsafeViewController(token: wallet.token, adapter: adapter, data: data)
        default: return nil
        }
    }
     
    // 跨链： wsafe => safe
    static func wsafeViewController(token: Token, adapter: ISendEthereumAdapter, data: Safe4Data) -> UIViewController {
        let evmAddressParserItem = EvmAddressParser()
        let udnAddressParserItem = UdnAddressParserItem.item(rawAddressParserItem: evmAddressParserItem, coinCode: token.coin.code, token: token)

        let addressParserChain = AddressParserChain()
                .append(handler: evmAddressParserItem)
                .append(handler: udnAddressParserItem)

        if let httpSyncSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .ethereum),
           let ensAddressParserItem = EnsAddressParserItem(rpcSource: httpSyncSource.rpcSource, rawAddressParserItem: evmAddressParserItem) {
            addressParserChain.append(handler: ensAddressParserItem)
        }

        let addressUriParser = AddressParserFactory.parser(blockchainType: token.blockchainType, tokenType: token.type)
        
        let addressService = AddressService(
                mode: .parsers(addressUriParser, addressParserChain),
                marketKit: App.shared.marketKit,
                contactBookManager: App.shared.contactManager,
                blockchainType: token.blockchainType,
                initialAddress: data.reciverAddress
        )

        let service = SendWsafeService(token: token, adapter: adapter, addressService: addressService)

        let switchService = AmountTypeSwitchService(userDefaultsStorage: App.shared.userDefaultsStorage)
        let fiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        switchService.add(toggleAllowedObservable: fiatService.toggleAvailableObservable)

        let coinService = CoinService(token: token, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)

        let viewModel = SendWsafeViewModel(service: service)
        
        if let wsafeWallet = data.wsafeWallet, let safeWallet = data.safeWallet {
            viewModel.onEnterAddress(wsafeWallet: wsafeWallet, safeWallet: safeWallet, address: data.reciverAddress)
        }
        
        let availableBalanceViewModel = SendAvailableBalanceViewModel(service: service, coinService: coinService, switchService: switchService)

        let amountViewModel = AmountInputViewModel(
                service: service,
                fiatService: fiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        addressService.amountPublishService = amountViewModel

        let recipientViewModel = RecipientAddressViewModel(service: addressService, handlerDelegate: nil)

        let viewController = SendSafeEvmViewController(
                evmKitWrapper: adapter.evmKitWrapper,
                viewModel: viewModel,
                availableBalanceViewModel: availableBalanceViewModel,
                amountViewModel: amountViewModel,
                recipientViewModel: recipientViewModel
        )
        var title = ""
        
        if data.isETH {
            title = "SAFE ERC20 => SAFE"
        } else if data.isMatic {
            title = "SAFE MATIC => SAFE"
        }else {
            title = "SAFE BEP20 => SAFE"
        }
        
        viewController.title = title
        return ThemeNavigationController(rootViewController: viewController)
    }

}
