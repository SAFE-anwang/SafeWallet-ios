import Foundation
import RxSwift
import RxRelay
import CurrencyKit
import MarketKit

protocol IWalletCoinPriceServiceDelegate: AnyObject {
    func didUpdateBaseCurrency()
    func didUpdate(itemsMap: [String: WalletCoinPriceService.Item])
}

class WalletCoinPriceService {
    weak var delegate: IWalletCoinPriceServiceDelegate?

    private let currencyKit: CurrencyKit.Kit
    private let marketKit: MarketKit.Kit
    private let safeCoinPriceManager: SafeCoinPriceManager

    private let disposeBag = DisposeBag()
    private var coinPriceDisposeBag = DisposeBag()

    private(set) var currency: Currency
    private var coinUids = Set<String>()
    private var safeCoinUids = Set<String>()


    init(currencyKit: CurrencyKit.Kit, marketKit: MarketKit.Kit) {
        self.currencyKit = currencyKit
        self.marketKit = marketKit

        currency = currencyKit.baseCurrency
        safeCoinPriceManager = App.shared.safeCoinPriceManager
        subscribe(disposeBag, currencyKit.baseCurrencyUpdatedObservable) { [weak self] baseCurrency in
            self?.onUpdate(baseCurrency: baseCurrency)
        }
    }

    private func onUpdate(baseCurrency: Currency) {
        currency = baseCurrency
        subscribeToCoinPrices()
        delegate?.didUpdateBaseCurrency()
    }

    private func subscribeToCoinPrices() {
        coinPriceDisposeBag = DisposeBag()
        
        subscribe(coinPriceDisposeBag, marketKit.coinPriceMapObservable(coinUids: Array(coinUids), currencyCode: currencyKit.baseCurrency.code)) { [weak self] in
            self?.onUpdate(coinPriceMap: $0)
            guard (self?.safeCoinUids.count ?? 0) > 0 else { return }
            self?.refershSafeCoinPrices()
        }
    }

    private func onUpdate(coinPriceMap: [String: CoinPrice]) {
        let itemsMap = coinPriceMap.mapValues { item(coinPrice: $0) }
        delegate?.didUpdate(itemsMap: itemsMap)
    }

    private func item(coinPrice: CoinPrice) -> Item {
        let currency = currencyKit.baseCurrency

        return Item(
                price: CurrencyValue(currency: currency, value: coinPrice.value),
                diff: coinPrice.diff,
                expired: coinPrice.expired
        )
    }

    private func filteredIds(tokens: [Token]) -> Set<String> {
        var uids = Set<String>()

        for token in tokens {
            if !token.isCustom {
                uids.insert(token.coin.uid)
            }
        }
        return uids
    }
}

extension WalletCoinPriceService {

    func set(tokens: Set<Token>) {
        let filteredIds = filteredIds(tokens: Array(tokens))
        guard coinUids != filteredIds else {
            return
        }
        coinUids = filteredIds
        safeCoinUids = filteredCustomIds(tokens: Array(tokens))
        subscribeToCoinPrices()
    }

    func itemMap(tokens: [Token]) -> [String: Item] {

        let items = marketKit.coinPriceMap(coinUids: Array(filteredIds(tokens: tokens)), currencyCode: currency.code).mapValues { item(coinPrice: $0) }
        let safeItems = safeCoinPriceManager.coinPriceMap(coinUids: Array(filteredCustomIds(tokens: Array(tokens))), currencyCode: currency.code).mapValues { item(safeCoinPrice: $0) }
        let temps = items.merging(safeItems){ (current, _) in current }
        return temps
    }

    func item(token: Token) -> Item? {
        marketKit.coinPrice(coinUid: token.coin.uid, currencyCode: currency.code).map { item(coinPrice: $0) }
    }
 
    func refresh() {
        marketKit.refreshCoinPrices(currencyCode: currency.code)
    }

}

extension WalletCoinPriceService {
    
    private func filteredCustomIds(tokens: [Token]) -> Set<String> {
        var uids = Set<String>()
        for token in tokens {
            if token.coin.name == safeCoinName {
                uids.insert(safeCoinUid)
            }
        }
        return uids
    }
    
    private func refershSafeCoinPrices() {
        safeCoinPriceManager.coinPriceValueSingle(coinUids: Array(safeCoinUids), currencyCode: currency.code)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .utility))
            .subscribe(onSuccess: { [weak self] prices in
                if let self = self {
                    let itemsMap = prices.mapValues{ self.item(safeCoinPrice: $0) }
                    let items = self.marketKit.coinPriceMap(coinUids: Array(self.coinUids), currencyCode: self.currency.code).mapValues { self.item(coinPrice: $0) }
                    let temps = itemsMap.merging(items){ (current, _) in current }
                    self.delegate?.didUpdate(itemsMap: temps)
                }
            })
            .disposed(by: disposeBag)
    }

    private func item(safeCoinPrice: SafeCoinPrice) -> Item {
        let currency = currencyKit.baseCurrency
        return Item(
                price: CurrencyValue(currency: currency, value: safeCoinPrice.value),
                diff: safeCoinPrice.diff,
                expired: safeCoinPrice.expired
        )
    }
}
extension WalletCoinPriceService {

    struct Item {
        let price: CurrencyValue
        let diff: Decimal?
        let expired: Bool
    }

}

