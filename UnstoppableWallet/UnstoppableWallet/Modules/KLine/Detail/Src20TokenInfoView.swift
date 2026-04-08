import SwiftUI
import MarketKit
import Kingfisher

struct Src20TokenInfoView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: Src20TokenInfoViewModel
    init(provider: Safe4Provider, token: MarketKit.Token) {
        _viewModel = StateObject(wrappedValue: Src20TokenInfoViewModel(provider: provider, token: token))
    }
    var body: some View {
        ThemeNavigationStack {
            ScrollableThemeView {
                VStack(spacing: .margin8) {
                    ListSectionHeader(text: "kline.safe_usdt_price".localized)
                    ListSection {
                        ListForEach(viewModel.viewItems) { item in
                            cell(item: item)
                        }
                    }
                    ListSectionHeader(text: "kline.asset_details".localized)
                    ListSection {
                        tokenInfoView()
                    }
                }
                .padding(EdgeInsets(top: .margin2, leading: .margin16, bottom: .margin32, trailing: .margin16))
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("kline.asset_details".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("button.close".localized) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }

    }


    @ViewBuilder func cell(item: KLineWSafeTokenPriceModel) -> some View {
        Cell(
            left: {
                KFImage.url(URL(string: item.logoURI))
                    .placeholder({
                        Image(viewModel.token.placeholderImageName)
                    })
                    .resizable()
                    .frame(size: .iconSize32)
            },
            middle: {
                MultiText(
                    title: item.symbol,
                    badge: "SRC20",
                    subtitle: "$\(priceFormatter.string(from: (Decimal(string: item.price) ?? 0) as NSNumber) ?? "--")",
                    subtitle2: " (\(Diff.text(diff: Decimal(string: item.change), expired: false)))"
                )
            },
            right: {
                RightMultiText(
                    title: usdtReservesFormatter.string(from: (Decimal(string: item.usdtReserves) ?? 0) as NSNumber),
                    subtitle: ""
                )
            },
            action: nil
        )
    }
    
    @ViewBuilder func tokenInfoView() -> some View {
        VStack {
            HStack{
                KFImage.url(URL(string: viewModel.currentToken?.logoURI ?? viewModel.token.coin.imageUrl))
                    .placeholder({
                        Image(viewModel.token.placeholderImageName)
                    })
                    .resizable()
                    .frame(size: .iconSize48)
                VStack {
                    Text("kline.asset_name".localized)
                        .themeSubhead1(alignment: .trailing)
                    Text(viewModel.currentToken?.name ?? viewModel.token.coin.name)
                        .themeSubhead1(color: .themeLeah, alignment: .trailing)
                    Text("kline.asset_symbol".localized)
                        .themeSubhead1(alignment: .trailing)
                    Text(viewModel.currentToken?.symbol ?? viewModel.token.coin.code)
                        .themeSubhead1(color: .themeLeah, alignment: .trailing)
                }
            }
            HorizontalDivider()
            VStack(spacing: .margin8) {
                Text("SRC20_Info_Contract".localized)
                    .themeSubhead1()
                Text(viewModel.currentToken?.address ?? viewModel.address)
                    .themeSubhead1(color: .blue)
                    .onTapGesture {
                        if let address = viewModel.currentToken?.address {
                            CopyHelper.copyAndNotify(value: address)
                        }
                    }
                HStack{
                    Text("SRC20_Deploy_Supply".localized)
                        .themeSubhead1()
                    Text("kline.feature".localized)
                        .themeSubhead1(alignment: .trailing)
                }
                HStack{
                    Text("\(viewModel.totalSupply) \(viewModel.currentToken?.symbol ?? "")")
                        .themeSubhead1(color: .themeLeah)
                    Text("\(viewModel.canAdditionalIssuance ? "kline.can_additional_issuance".localized : "kline.cannot_additional_issuance".localized)")
                        .themeSubhead1(color: .themeGreen, alignment: .trailing)
                }
            }
            HorizontalDivider()
            HStack {
                Label("kline.warning_external_link".localized, image: "circle_warning_24")
            }
            HorizontalDivider()
            VStack(spacing: .margin16) {
                Text("kline.asset_description".localized)
                    .themeSubhead1()
                Text("\(viewModel.description)")
                    .themeSubhead1(color: .themeLeah)
                
            }
        }
        .padding(EdgeInsets(top: .margin16, leading: .margin16, bottom: .margin32, trailing: .margin16))
    }
    
    
    private let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfEven
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter
    }()
    
    private let usdtReservesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfEven
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

