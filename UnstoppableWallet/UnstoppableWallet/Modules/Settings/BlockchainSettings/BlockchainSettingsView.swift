import Kingfisher
import MarketKit
import SwiftUI

struct BlockchainSettingsView: View {
    @ObservedObject var viewModel: BlockchainSettingsViewModel

    @State private var btcSheetBlockchain: Blockchain?
    @State private var evmSheetBlockchain: Blockchain?

    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin32) {
                ListSection {
                    ForEach(viewModel.btcItems, id: \.blockchain.uid) { item in
                        ClickableRow(action: {
                            stat(page: .blockchainSettings, event: .openBlockchainSettingsBtc(chainUid: item.blockchain.uid))
                            btcSheetBlockchain = item.blockchain
                        }) {
                            ItemView(
                                blockchain: item.blockchain,
                                value: item.title
                            )
                        }
                    }
                    .sheet(item: $btcSheetBlockchain) { blockchain in
                        ThemeNavigationView { BtcBlockchainSettingsModule.view(blockchain: blockchain) }
                    }
                }

                ListSection {
                    ForEach(viewModel.evmItems, id: \.blockchain.uid) { item in
                        ClickableRow(action: {
                            stat(page: .blockchainSettings, event: .openBlockchainSettingsEvm(chainUid: item.blockchain.uid))
                            evmSheetBlockchain = item.blockchain
                        }) {
                            ItemView(
                                blockchain: item.blockchain,
                                value: item.syncSource.name
                            )
                        }
                    }
                    .sheet(item: $evmSheetBlockchain) { blockchain in
                        EvmNetworkView(blockchain: blockchain).ignoresSafeArea()
                    }
                }
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationTitle("blockchain_settings.title".localized)
    }

    struct ItemView: View {
        let blockchain: Blockchain
        let value: String

        var body: some View {
            KFImage.url(URL(string: blockchain.type.imageUrl))
                .resizable()
                .frame(width: .iconSize32, height: .iconSize32)

            VStack(spacing: 1) {
                Text(blockchain.name).themeBody()
                Text(value).themeSubhead2()
            }

            Image.disclosureIcon
        }
    }
}
