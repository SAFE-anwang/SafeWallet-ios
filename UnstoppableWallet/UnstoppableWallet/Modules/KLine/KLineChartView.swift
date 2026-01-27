import SwiftUI
import SwiftKLine
import MarketKit
import Kingfisher

enum ChartDisplayMode: String, CaseIterable, Identifiable {
    case candlestick
    case timeSeries
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .candlestick: return "K线"
        case .timeSeries: return "分时"
        }
    }
}

struct KLineChartView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: KLineChartViewModel
    @State private var period: KLinePeriod = .oneMinute
    @State private var chartMode: ChartDisplayMode = .candlestick
    let provider: Safe4Provider
    let token0: MarketKit.Token
    let token1: MarketKit.Token
    init(provider: Safe4Provider, token0: MarketKit.Token, token1: MarketKit.Token) {
        self.provider = provider
        self.token0 = token0
        self.token1 = token1
        _viewModel = StateObject(wrappedValue: KLineChartViewModel(provider: provider, token0: token0, token1: token1))
    }
    var body: some View {
        ThemeView {
            ScrollView {
                VStack(spacing: 16) {
                    priceView()
                    KLinePeriodPicker(period: $period)
                    KLineSwiftUIView(period: period, mode: chartMode, provider: provider, token0: token0, token1: token1)
                }
            }
        }
        .navigationTitle("market.category.overview".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("button.close".localized) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
    
    @ViewBuilder func priceView() -> some View {
        if let price = viewModel.price {
            VStack {
                HStack(spacing: .margin4) {
//                    KFImage(URL(string: price.logoURI))
//                        .resizable()
//                        .frame(size: 40)
                    VStack {
                        Text("\(token0.coin.name)/USDT")
                            .themeHeadline1()
                        HStack(spacing: .margin4) {
                            Text("$\(price.price)")
                                .themeSubhead2()
                            Text("\(price.change) %")
                                .themeSubhead2()
                        }
                    }
                }
            }
            .padding(.horizontal, .margin16)
        } else {
            VStack {
                Text("\(token0.coin.code)/\(token1.coin.code)")
            }
        }
    }
}
