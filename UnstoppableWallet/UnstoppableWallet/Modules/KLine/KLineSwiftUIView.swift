import SwiftUI
import SwiftKLine
import MarketKit

struct KLineSwiftUIView: View {
    
    let period: KLinePeriod
    let mode: ChartDisplayMode
    let provider: Safe4Provider
    let token0: MarketKit.Token
    let token1: MarketKit.Token
    
    var body: some View {
        KLineRepresentable(period: period, mode: mode, provider: provider, token0: token0, token1: token1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct KLineRepresentable: UIViewRepresentable {
    
    let period: KLinePeriod
    let mode: ChartDisplayMode
    let provider: Safe4Provider
    let token0: MarketKit.Token
    let token1: MarketKit.Token
    
    typealias UIViewType = KLineView

    func makeUIView(context: Context) -> KLineView {
        let config = KLineConfiguration.themed(.customPreset)
        let store = UserDefaultsIndicatorSelectionStore()
        store.save(state: IndicatorSelectionState())
        let view = KLineView(configuration: config, indicatorSelectionStore: store)
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateUIView(_ uiView: KLineView, context: Context) {
        if context.coordinator.period != period {
            context.coordinator.error = nil

            if context.coordinator.dataProvider == nil {
                context.coordinator.dataProvider = SafeKLineDataProvider(period: period, provider: provider, token0: token0, token1: token1)
            } else {
                let _ = context.coordinator.dataProvider?.updatePeriod(period)
            }

            if let dataProvider = context.coordinator.dataProvider {
                context.coordinator.period = period
                Task {
                    do {
                        _ = try await dataProvider.reloadData()
                    } catch {
                        await MainActor.run {
                            context.coordinator.error = error
                        }
                    }
                }
            }
        }
    }

    final class Coordinator {
        var period: KLinePeriod = .fourHours
        var dataProvider: SafeKLineDataProvider?
        var error: Error?
        var retryCount: Int = 0

        func retry() {
            retryCount += 1
            dataProvider = nil
        }
    }
}

extension KLineConfiguration.ThemePreset {
    static var customPreset: KLineConfiguration.ThemePreset {
        let candle = CandleStyle(
            risingColor: UIColor(red: 0.12, green: 0.84, blue: 0.72, alpha: 1),
            fallingColor: UIColor(red: 0.96, green: 0.32, blue: 0.48, alpha: 1),
            width: 9,
            gap: 2
        )
        let layout = LayoutMetrics(
            mainChartHeight: 340,
            timelineHeight: 18,
            indicatorHeight: 76,
            indicatorSelectorHeight: 36
        )
        let indicatorStyles: [Indicator.Key: any IndicatorStyle] = [
            .ma(5): LineStyle(strokeColor: UIColor(red: 1, green: 0.78, blue: 0.32, alpha: 1)),
            .ma(10): LineStyle(strokeColor: UIColor(red: 0.97, green: 0.5, blue: 0.67, alpha: 1)),
            .ma(20): LineStyle(strokeColor: UIColor(red: 0.4, green: 0.85, blue: 1, alpha: 1)),
            .ema(5): LineStyle(strokeColor: UIColor(red: 0.92, green: 0.68, blue: 1, alpha: 1)),
            .ema(10): LineStyle(strokeColor: UIColor(red: 0.47, green: 0.87, blue: 0.98, alpha: 1)),
            .ema(20): LineStyle(strokeColor: UIColor(red: 0.32, green: 0.71, blue: 1, alpha: 1)),
            .wma(5): LineStyle(strokeColor: UIColor(red: 0.63, green: 0.89, blue: 0.75, alpha: 1)),
            .wma(10): LineStyle(strokeColor: UIColor(red: 0.74, green: 0.8, blue: 0.98, alpha: 1)),
            .wma(20): LineStyle(strokeColor: UIColor(red: 0.97, green: 0.84, blue: 0.96, alpha: 1)),
            .boll: LineStyle(strokeColor: UIColor(red: 0.64, green: 0.78, blue: 1, alpha: 1)),
            .sar: LineStyle(strokeColor: UIColor(red: 1, green: 0.71, blue: 0.45, alpha: 1)),
            .rsi(6): LineStyle(strokeColor: UIColor(red: 0.83, green: 0.93, blue: 1, alpha: 1)),
            .rsi(12): LineStyle(strokeColor: UIColor(red: 1, green: 0.77, blue: 0.53, alpha: 1)),
            .rsi(24): LineStyle(strokeColor: UIColor(red: 0.58, green: 0.89, blue: 0.71, alpha: 1)),
            .macd: MACDStyle(
                macdColor: UIColor(red: 0.97, green: 0.69, blue: 0.36, alpha: 1),
                difColor: UIColor(red: 0.63, green: 0.89, blue: 1, alpha: 1),
                deaColor: UIColor(red: 1, green: 0.47, blue: 0.64, alpha: 1)
            )
        ]
        return KLineConfiguration.ThemePreset(
            candleStyle: candle,
            legendFont: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            watermarkText: "",
            layout: layout,
            indicatorStyles: indicatorStyles
        )
    }
}
