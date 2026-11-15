import Combine
import Foundation
import MarketKit

protocol IWalletCoinPriceServiceDelegate: AnyObject {
    func didUpdate(itemsMap: [String: WalletCoinPriceService.Item]?)
}

class WalletCoinPriceService {
    weak var delegate: IWalletCoinPriceServiceDelegate?

    private let currencyManager = Core.shared.currencyManager
    private let priceChangeModeManager = Core.shared.priceChangeModeManager
    private let marketKit = Core.shared.marketKit
    private var cancellables = Set<AnyCancellable>()
    private var coinPriceCancellables = Set<AnyCancellable>()
    private let priceQueue = DispatchQueue(label: "\(AppConfig.label).wallet-coin-price-service", qos: .userInitiated)

    private var _currency: Currency
    private var coinUids = Set<String>()
    private var feeCoinUids = Set<String>()
    private var conversionCoinUids = Set<String>()

    init() {
        _currency = currencyManager.baseCurrency

        currencyManager.$baseCurrency
            .sink { [weak self] currency in
                self?.onUpdate(baseCurrency: currency)
            }
            .store(in: &cancellables)

        priceChangeModeManager.$priceChangeMode
            .sink { [weak self] _ in
                self?.delegate?.didUpdate(itemsMap: nil)
            }
            .store(in: &cancellables)
    }

    private func onUpdate(baseCurrency: Currency) {
        priceQueue.async {
            self._currency = baseCurrency
            self.subscribeToCoinPrices()
            self.delegate?.didUpdate(itemsMap: nil)
        }
    }

    private func subscribeToCoinPrices() {
        coinPriceCancellables = Set()

        let currencyCode = _currency.code

        subscribe(coinUids: coinUids, currencyCode: currencyCode) { [weak self] coinPriceMap in
            self?.onUpdate(coinPriceMap: coinPriceMap, currencyCode: currencyCode)
        }
        subscribe(coinUids: feeCoinUids, currencyCode: currencyCode) { _ in }
        subscribe(coinUids: conversionCoinUids, currencyCode: currencyCode) { _ in }
    }

    private func subscribe(coinUids: Set<String>, currencyCode: String, onUpdate: @escaping ([String: CoinPrice]) -> Void) {
        guard !coinUids.isEmpty else {
            return
        }

        marketKit.walletCoinPriceMapPublisher(coinUids: Array(coinUids), currencyCode: currencyCode)
            .sink(receiveValue: onUpdate)
            .store(in: &coinPriceCancellables)
    }

    private func onUpdate(coinPriceMap: [String: CoinPrice], currencyCode: String) {
        priceQueue.async {
            guard self._currency.code == currencyCode else {
                return
            }

            // Updates contain only one price source. Read the complete persisted
            // snapshot so a SAFE update preserves regular prices loaded before
            // this subscription, including when their endpoint is unavailable.
            var prices = self.marketKit.walletCoinPriceMap(
                coinUids: Array(self.coinUids), currencyCode: currencyCode
            )
            prices.merge(coinPriceMap.filter { self.coinUids.contains($0.key) }) { _, updated in updated }
            self.delegate?.didUpdate(itemsMap: prices.mapValues(self.item(coinPrice:)))
        }
    }

    private func item(coinPrice: CoinPrice) -> Item {
        let diff: Decimal?
        switch priceChangeModeManager.priceChangeMode {
        case .hour24:
            diff = coinPrice.diff24h
        case .day1:
            diff = coinPrice.diff1d
        }

        return Item(
            price: CurrencyValue(currency: _currency, value: coinPrice.value),
            diff: diff,
            expired: coinPrice.expired
        )
    }
}

extension WalletCoinPriceService {
    func set(coinUids: Set<String>, feeCoinUids: Set<String> = Set(), conversionCoinUids: Set<String> = Set()) {
        priceQueue.async {
            guard self.coinUids != coinUids || self.feeCoinUids != feeCoinUids || self.conversionCoinUids != conversionCoinUids else {
                return
            }

            self.coinUids = coinUids
            self.feeCoinUids = feeCoinUids
            self.conversionCoinUids = conversionCoinUids

            self.subscribeToCoinPrices()
        }
    }

    func itemMap(coinUids: [String]) -> [String: Item] {
        priceQueue.sync {
            marketKit.walletCoinPriceMap(coinUids: coinUids, currencyCode: _currency.code).mapValues(item(coinPrice:))
        }
    }

    func item(coinUid: String) -> Item? {
        priceQueue.sync {
            marketKit.walletCoinPrice(coinUid: coinUid, currencyCode: _currency.code).map(item(coinPrice:))
        }
    }

    func refresh() {
        priceQueue.sync {
            marketKit.refreshCoinPrices(currencyCode: _currency.code)
        }
    }
}

extension WalletCoinPriceService {
    var currency: Currency {
        priceQueue.sync { _currency }
    }
}

extension WalletCoinPriceService {
    struct Item: Hashable {
        let price: CurrencyValue
        let diff: Decimal?
        let expired: Bool
    }
}
