import SwiftKLine
import Foundation
import MarketKit
import RxSwift
import ObjectMapper

final class SafeKLineDataProvider: KLineItemProvider {
    private var disposeBag = DisposeBag()
    private let period: KLinePeriod
    private lazy var endDate = Date()
    
    private let provider: Safe4Provider
    private let token0: MarketKit.Token
    private let token1: MarketKit.Token
    
    var originalData = [SafeKLineItem]()
    
    init(period: KLinePeriod = .thirtyMinutes, provider: Safe4Provider, token0: MarketKit.Token, token1: MarketKit.Token) {
        self.period = period
        self.provider = provider
        self.token0 = token0
        self.token1 = token1
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
        if originalData.isEmpty {
            return try await fetchKLineItemsFromProvider()
        }else {
            return []
        }
    }
    
    func fetchKLineItems(from start: Date, to end: Date) async throws -> [any SwiftKLine.KLineItem] {
        if originalData.isEmpty {
            return try await fetchKLineItemsFromProvider()
        }else {
            return []
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
            provider.marketkLinesSingle(token0: token0Addr, token1: token1Addr, interval: intervalToString(period.seconds < 2800 ? .thirtyMinutes : period ))
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onSuccess: { datas in
                    let sortedData = datas.sorted { $0.timestamp < $1.timestamp }
                    self.originalData = sortedData
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
    let value: Double = 0       // 成交额
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
