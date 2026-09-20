import Foundation
import SwiftUI
import UIKit
import MarketKit
import EvmKit
import BigInt
import UniswapKit

class LiquidityRecordModule {

    static func subViewController(dexType: UniswapKit.DexType, blockchainType: BlockchainType) -> LiquidityRecordViewController {

        let v2Service = LiquidityRecordService(
            marketKit: Core.shared.marketKit,
            walletManager: Core.shared.walletManager,
            adapterManager: Core.shared.adapterManager,
            blockchainType: blockchainType
        )

        let v3Service = LiquidityV3RecordService(
            dexType: dexType,
            marketKit: Core.shared.marketKit,
            walletManager: Core.shared.walletManager,
            adapterManager: Core.shared.adapterManager,
            blockchainType: blockchainType
        )

        let viewModel =  LiquidityRecordViewModel(service: v2Service)
        let v3ViewModel =  LiquidityV3RecordViewModel(service: v3Service)
        let viewController = LiquidityRecordViewController(viewModel: viewModel, v3ViewModel: v3ViewModel)

        return viewController
    }

    static func removeConfirmViewController(viewModel: LiquidityRecordViewModel, recordItem: LiquidityRecordViewModel.RecordItem) -> UIViewController? {
        UIHostingController(
            rootView: LiquidityRemoveHostingView(
                displayData: .v2(
                    token0: recordItem.tokenA,
                    token1: recordItem.tokenB,
                    amount0: recordItem.amountAStr,
                    amount1: recordItem.amountBStr,
                    liquidity: recordItem.liquidityDec
                ),
                makeSendData: { ratio in
                    SendData.liquidityRemove(
                        request: LiquidityRemoveRequest(blockchainType: recordItem.tokenA.blockchainType) {
                            LiquidityRemoveSendHandler.v2(item: recordItem, ratio: ratio, service: viewModel.service)
                        }
                    )
                },
                onSuccess: { viewModel.refresh() }
            )
        )
    }

    enum Tab: Int, CaseIterable {
        case safe
        case bsc
        case eth

        var title: String {
            switch self {
            case .safe: return "SAFE"
            case .bsc: return "BSC".localized
            case .eth: return "ETH".localized
            }
        }
    }
}

/// Compatibility host for callers that still ask the module for a UIViewController.
/// The old UIKit confirmation controller is intentionally unavailable; this keeps the
/// public module boundary stable while routing those callers through SendNew.
private struct LiquidityRemoveHostingView: View {
    private let displayData: LiquidityRemoveDisplayData
    private let makeSendData: (BigUInt) -> SendData
    private let onSuccess: () -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var isPresented = true

    init(displayData: LiquidityRemoveDisplayData, makeSendData: @escaping (BigUInt) -> SendData, onSuccess: @escaping () -> Void) {
        self.displayData = displayData
        self.makeSendData = makeSendData
        self.onSuccess = onSuccess
    }

    var body: some View {
        LiquidityRemoveSendView(isPresented: $isPresented, displayData: displayData, makeSendData: makeSendData) {
            onSuccess()
            presentationMode.wrappedValue.dismiss()
        }
    }
}

struct LiquidityRecordView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewController: LiquidityRecordViewController
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return viewController
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

struct LiquidityViewRepresentable: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return ThemeNavigationController(rootViewController: viewController)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
