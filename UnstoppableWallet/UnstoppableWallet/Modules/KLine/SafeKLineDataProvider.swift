import SwiftKLine
import Foundation
import MarketKit
import RxSwift
import ObjectMapper

final class SafeKLineDataProvider: KLineItemProvider {

    
    private var disposeBag = DisposeBag()
    private var period: KLinePeriod
    private lazy var endDate = Date()
    
    private let provider: Safe4Provider
    private let token0: MarketKit.Token
    private let token1: MarketKit.Token
    
    private var cachedData: [KLinePeriod: [SafeKLineItem]] = [:]
    
    var originalData: [SafeKLineItem] {
        return cachedData[period] ?? []
    }
    
    init(period: KLinePeriod = .fourHours, provider: Safe4Provider, token0: MarketKit.Token, token1: MarketKit.Token) {
        self.period = period
        self.provider = provider
        self.token0 = token0
        self.token1 = token1
    }
    
    func updatePeriod(_ newPeriod: KLinePeriod) -> [SafeKLineItem] {
        self.period = newPeriod
        return originalData
    }
    
    func reloadData() async throws -> [SafeKLineItem] {
        return try await fetchKLineItemsFromProvider()
    }

    
    private func intervalToString(_ interval: KLinePeriod) -> String {
        switch interval {
        case .oneMinute:
            return "1m"
        case .fiveMinutes:
            return "5m"
        case .fifteenMinutes:
            return "15m"
        case .thirtyMinutes:
            return "30m"
        case .oneHour:
            return "1h"
        case .fourHours:
            return "4h"
        case .oneDay:
            return "1d"
        case .oneWeek:
            return "1w"
        case .oneMonth:
            return "1M"
        default:
            return "4h"
        }
    }
    
    func fetchKLineItems(forPage page: Int) async throws -> [any KLineItem] {
        return []
    }
    
    func fetchKLineItems(from start: Date, to end: Date) async throws -> [any SwiftKLine.KLineItem] {
        return []
    }
    
    func liveStream() -> AsyncStream<any KLineItem> {
        AsyncStream {continuation in
            Task {
                do {
                    let cachedItems = cachedData[period] ?? []
                    if !cachedItems.isEmpty {
                        for item in cachedItems {
                            continuation.yield(item)
                        }
                    }else {
                        let newItems = try await fetchKLineItemsFromProvider()
                        for item in newItems {
                            continuation.yield(item)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }
            
    private func fetchKLineItemsFromProvider() async throws -> [SafeKLineItem] {
        
        guard case let .eip20(token0Address) = token0.type, case let .eip20(token1Address) = token1.type else {
            throw NSError(domain: "SafeKLineDataProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid token types"])
        }
        let token0Addr: String
        let token1Addr: String
            
        if !token0.isSafeUSDT() && token1.isSafeUSDT() {
            token0Addr = token1Address
            token1Addr = token0Address
        }else {
            token0Addr = token0Address
            token1Addr = token1Address
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let p = period.seconds < KLinePeriod.thirtyMinutes.seconds ? KLinePeriod.thirtyMinutes : period
            provider.marketkLinesSingle(token0: token0Addr, token1: token1Addr, interval: p.identifier)
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onSuccess: { datas in
                    let sortedData = datas.sorted { $0.timestamp < $1.timestamp }
                    self.cachedData[self.period] = sortedData
                    continuation.resume(returning: sortedData)
                }, onError: { error in
                    continuation.resume(throwing: error)
                })
                .disposed(by: disposeBag)
        }
    }
}

struct SafeKLineItem: KLineItem, ImmutableMappable {
    let opening: Double
    let closing: Double
    let highest: Double
    let lowest: Double
    let volume: Double
    let value: Double = 0       
    let timestamp: Int
    
    init(map: Map) throws {
        opening = try map.value("open", using: StringToDoubleTransform())
        closing = try map.value("close", using: StringToDoubleTransform())
        highest = try map.value("high", using: StringToDoubleTransform())
        lowest = try map.value("low", using: StringToDoubleTransform())
        volume = try map.value("volumes", using: StringToDoubleTransform())
        timestamp = try map.value("timestamp", using: StringToIntTransform())
    }
}

class StringToDoubleTransform: TransformType {
    typealias Object = Double
    typealias JSON = Any
    
    func transformFromJSON(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        } else if let stringValue = value as? String {
            return Double(stringValue)
        }
        return nil
    }
    
    func transformToJSON(_ value: Double?) -> Any? {
        return value
    }
}

class StringToIntTransform: TransformType {
    typealias Object = Int
    typealias JSON = Any
    
    func transformFromJSON(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        } else if let stringValue = value as? String {
            return Int(stringValue)
        }
    
        return nil
    }
    
    func transformToJSON(_ value: Int?) -> Any? {
        return value
    }
}

extension KLinePeriod: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(seconds)
        hasher.combine(identifier)
    }
}
