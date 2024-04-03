import Kingfisher
import SwiftUI

struct TransactionBlockchainSelectView: View {
    @ObservedObject var viewModel: TransactionBlockchainSelectViewModel

    @Environment(\.presentationMode) private var presentationMode

    init(transactionFilterViewModel: TransactionFilterViewModel) {
        _viewModel = ObservedObject(wrappedValue: TransactionBlockchainSelectViewModel(transactionFilterViewModel: transactionFilterViewModel))
    }

    var body: some View {
        ScrollableThemeView {
            ListSection {
                ClickableRow(action: {
                    viewModel.set(currentBlockchain: nil, blockchainUIds: nil)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image("blocks_24").themeIcon()
                    Text("transaction_filter.all_blockchains").themeBody()

                    if viewModel.currentBlockchain == nil {
                        Image.checkIcon
                    }
                }
                
                ForEach(viewModel.allBlockchainSeries, id: \.id) { series in
                    ClickableRow(action: {
                        viewModel.set(currentBlockchain: .blockchainSeries(series: series), blockchainUIds: series.uids(blockchains: viewModel.blockchains))
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image("blocks_24").themeIcon()
                        Text(series.title).themeBody()

                        if case let .blockchainSeries(_series) = viewModel.currentBlockchain,  _series == series {
                            Image.checkIcon
                        }
                    }
                }


                ForEach(viewModel.blockchains, id: \.uid) { blockchain in
                    ClickableRow(action: {
                        viewModel.set(currentBlockchain: .blockchain(blockchain: blockchain), blockchainUIds: [blockchain.uid])
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        KFImage.url(URL(string: blockchain.type.imageUrl))
                            .resizable()
                            .frame(width: .iconSize32, height: .iconSize32)

                        Text(blockchain.name).themeBody()

                        if case let .blockchain(_blockchain) = viewModel.currentBlockchain,  _blockchain == blockchain {
                            Image.checkIcon
                        }
                    }
                }
            }
            .themeListStyle(.transparent)
            .padding(.bottom, .margin32)
        }
        .navigationTitle("transaction_filter.blockchain".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("button.cancel".localized) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
