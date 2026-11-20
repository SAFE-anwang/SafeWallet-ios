import Foundation
import MarketKit
import SwiftUI
import Testing
import UIKit
@testable import WalletCore

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SAFEWALLET_UNIT_TEST_HOST"] != "1", "Requires full app initialization and image assets"))
struct ForkProductPresentationTests {
    private func token(_ chain: BlockchainType, uid: String, type: TokenType = .native) -> Token {
        Token(coin: Coin(uid: uid, name: uid, code: uid.uppercased()),
              blockchain: Blockchain(type: chain, name: chain.uid, explorerUrl: nil),
              type: type, decimals: 18)
    }

    @Test func safePlaceholdersDoNotChangeOrdinaryTokenFallback() {
        #expect(CoinIconView(token: token(.safe, uid: "safe")).placeholderImage == "safe-anwang_trx_32")
        #expect(CoinIconView(token: token(.safe4, uid: "src20", type: .eip20(address: "0x1111111111111111111111111111111111111111"))).placeholderImage == "safe-anwang_trx_32")
        #expect(CoinIconView(token: token(.ethereum, uid: "ethereum")).placeholderImage == "placeholder_circle")
        #expect(CoinIconView(token: nil).placeholderImage == "placeholder_circle")
    }

    @Test func nativeSafeIconActuallyRendersOpacityAndSyncOverlay() throws {
        let native = token(.safe4, uid: safe4CoinUid)
        #expect(native.coin.isSafe4Native)
        func rendered(opacity: Double, overlay: AnyView? = nil) throws -> Data {
            let view = CoinIconView(token: native, iconOpacity: opacity, iconOverlay: overlay)
                .padding(10).background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return try #require(renderer.uiImage?.pngData())
        }
        let plain = try rendered(opacity: 1)
        let dimmed = try rendered(opacity: 0.5)
        let progress = try rendered(opacity: 1, overlay: AnyView(Text("50%").foregroundStyle(.red)))

        #expect(plain != dimmed)
        #expect(plain != progress)

        let board = HStack(spacing: 20) {
            BalanceCoinIconView(token: native, state: .synced, isReachable: true) {}
            BalanceCoinIconView(token: native, state: .syncing(progress: 50, remaining: nil, lastBlockDate: nil), isReachable: true) {}
            BalanceCoinIconView(token: native, state: .notSynced(error: "test"), isReachable: true) {}
        }.padding(24).background(Color.themeTyler).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: board)
        renderer.scale = 3
        let png = try #require(renderer.uiImage?.pngData())
        if #available(iOS 26.0, *) {
            Attachment.record(png, named: "safe-native-synced-syncing-failed.png")
        }
    }

    @Test func klinePairTracksSelectionsAndRejectsOtherChains() {
        let native = token(.safe4, uid: safe4CoinUid)
        let src20 = token(.safe4, uid: "src20", type: .eip20(address: "0x1111111111111111111111111111111111111111"))
        let model = MultiSwapViewModel(token: native, tokenOut: src20, autoResolveTokenOut: false)
        defer { model.stopAutoQuoting() }
        #expect(model.klinePair?.tokenIn == native)
        #expect(model.klinePair?.tokenOut == src20)
        model.tokenOut = token(.ethereum, uid: "ethereum")
        #expect(model.klinePair == nil)
        model.tokenOut = src20
        #expect(model.klinePair?.tokenOut == src20)
        model.tokenIn = nil
        #expect(model.klinePair == nil)
    }

    @Test func renderSwapToolbarWithSafe4Pair() async throws {
        let native = token(.safe4, uid: safe4CoinUid)
        let src20 = token(.safe4, uid: "src20", type: .eip20(address: "0x1111111111111111111111111111111111111111"))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: RegularMultiSwapView(token: native, tokenOut: src20).environment(\.colorScheme, .light))
        window.rootViewController = controller
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let png = UIGraphicsImageRenderer(bounds: controller.view.bounds).pngData { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if #available(iOS 26.0, *) { Attachment.record(png, named: "safe4-swap-toolbar.png") }
    }
}
