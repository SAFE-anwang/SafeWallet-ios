import Kingfisher
import SwiftUI
import ThemeKit
import UIExtensions
import SafariServices
import ComponentKit
import MarketKit
import Combine

struct MainSafeZoneView: View {
    @Environment(\.navigationController) var navController
    @State private var presentDestination: PresentDestination?
    @State private var linkUrl: URL?
    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin8) {
                SectionLockView()
                SectionSafe3LockView()
                SectionNodeView()
                SectionCrossETHView()
                SectionCrossBSCView()
                SectionCrossMATICView()
                SectionSafeSwapView()
                SectionWithdrawView()
                SectionSRC20View()
                SectionBasicInfoView()
            }
            .padding(EdgeInsets(top: .margin12, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("safe_zone.nav.title".localized)
        .sheet(item: $presentDestination) { reason in
            switch reason {
            case .lineLockRecoard:
                LineLockRecoardView()
                
            case let .crossChain(vc):
                Safe4CrossChainView(viewController: vc)
                
            case .safeSwapScr20:
                Safe4SwapSrc20View()
            }
        }
        .sheet(item: $linkUrl) { url in
            SFSafariView(url: url)
                .ignoresSafeArea()
        }

    }

    @ViewBuilder private func SectionLockView() -> some View {
        SafeListSectionHeader(text: "SAFE")
        ListSection {
            ClickableRow(action: {
                if let vc = SafeLineLockModule.viewController() {
                    navController?.pushViewController(vc, animated: true)
                }
            }) {
                ItemView(title: "safe_zone.row.linear".localized)
            }
            ClickableRow(action: {
                if let vc = SafeLineLockRecoardModule.viewController() {
                    navController?.pushViewController(vc, animated: true)
                }
            }) {
                ItemView(title: "safe_zone.row.lock".localized)
            }
        }
    }
    
    @ViewBuilder private func SectionSafe3LockView() -> some View {
        HStack(){
            TagCoinView(name: "SAFE",
                        nameFont: .themeSubhead1,
                        code: "SAFE3",
                        codeFont: .themeMicro
            )
            Text("锁仓")
                .themeSubhead1(color: .themeLeah)
                .fixedSize()
            Spacer()
        }.padding(EdgeInsets(top: .margin12, leading: 0, bottom: 0, trailing: 0))
        ListSection {
            ClickableRow(action: {
                if let vc = LineLockRecoardModule.viewController() {
                    navController?.pushViewController(vc, animated: true)
                }
            }) {
                ItemView(title: "safe_zone.row.lock".localized)
            }
        }
    }
    
    @ViewBuilder private func SectionNodeView() -> some View {
        SafeListSectionHeader(text: "SAFE")
        ListSection {
            ClickableRow(action: {
                guard let vc = SuperNodeModule.viewController() else{ return }
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "safe_zone.row.superNode".localized)
            }
            ClickableRow(action: {
                guard let vc = MasterNodeModule.viewController() else{ return }
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "safe_zone.row.masterNode".localized)
            }
            ClickableRow(action: {
                guard let vc = ProposalModule.viewController() else { return }
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "safe_zone.row.proposal".localized)
            }
            ClickableRow(action: {
                guard let nav = navController else { return }
                guard let vc = LockedRecordModule.viewController(nav: nav) else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "safe_zone.safe4.account.lock".localized)
            }
            ClickableRow(action: {
                guard let vc = RedeemSafe3Module.viewController() else { return }
                navController?.pushViewController(vc, animated: true)
            }) {
                TagItemView(text: "=> SAFE", name: "SAFE", code: "SAFE3", type: .left)
            }
            ClickableRow(action: {
                guard let vc = DrawSafe4Module.viewController() else { return }
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "SAFE领取".localized)
            }
        }
    }
    
    @ViewBuilder private func SectionCrossETHView() -> some View {
        SafeListSectionHeader(text: "safe_zone.section.cross_eth".localized)
        ListSection {
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .ETH, crossChainType: .safeCrossToWSafe, isSafe4: true) {
                    presentDestination = .crossChain(vc: vc)
                }
            })
            {
                TagItemView(text:  "SAFE =>", name: "SAFE", code: "ERC20", type: .right)
            }
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .ETH, crossChainType: .wsafeCrossToSafe, isSafe4: true) {
                    presentDestination = .crossChain(vc: vc)
                }
            }) {
                TagItemView(text:  "=> SAFE", name: "SAFE", code: "ERC20", type: .left)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://etherscan.io/token/0xEE9c1Ea4DCF0AAf4Ff2D78B6fF83AA69797B65Eb")
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://v2.info.uniswap.org/pair/0x8b04fdc8e8d7ac6400b395eb3f8569af1496ee33")
            }) {
                ItemView(title: "SAFE@uniswapv2")
            }
        }
    }
    
    @ViewBuilder private func SectionCrossBSCView() -> some View {
        SafeListSectionHeader(text: "safe_zone.section.cross_bsc".localized)
        ListSection {
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .BSC, crossChainType: .safeCrossToWSafe, isSafe4: true) {
                    presentDestination = .crossChain(vc: vc)
                }
            }) {
                TagItemView(text:  "SAFE =>", name: "SAFE", code: "BEP20", type: .right)
            }
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .BSC, crossChainType: .wsafeCrossToSafe, isSafe4: true) {
                    presentDestination = .crossChain(vc: vc)
                }
            }) {
                TagItemView(text:  "=> SAFE", name: "SAFE", code: "BEP20", type: .left)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://bscscan.com/token/0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1")
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://pancakeswap.finance/info/pool/0x400db103af7a0403c9ab014b2b73702b89f6b4b7")
            }) {
                ItemView(title: "SAFE@pancakeswap")
            }
        }
    }
    
    @ViewBuilder private func SectionCrossMATICView() -> some View {
        SafeListSectionHeader(text: "safe_zone.section.cross_matic".localized)
        ListSection {
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .MATIC, crossChainType: .safeCrossToWSafe, isSafe4: true) {
                    presentDestination = .crossChain(vc: vc)
                }
            }) {
                TagItemView(text:  "SAFE =>", name: "SAFE", code: "MATIC", type: .right)
            }
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .MATIC, crossChainType: .wsafeCrossToSafe, isSafe4: true) {
                    presentDestination = .crossChain(vc: vc)
                }
            }) {
                TagItemView(text:  "=> SAFE", name: "SAFE", code: "MATIC", type: .left)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://polygonscan.com/address/0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779")
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
        }

    }
    
    @ViewBuilder private func SectionSafeSwapView() -> some View {
        HStack(){
            Text("SAFE兑换")
                .themeSubhead1(color: .themeLeah)
                .fixedSize()
            TagCoinView(name: "SAFE",
                        nameFont: .themeSubhead1,
                        code: "SRC20",
                        codeFont: .themeMicro
            )
            Spacer()
        }.padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))
        ListSection {
            ClickableRow(action: {
                if let _ = Safe4SwapModule.viewController() {
                    presentDestination = .safeSwapScr20
                }
            }) {
                TagItemView(text:  "SAFE <=>", name: "SAFE", code: "SRC20", type: .right)
            }
        }
    }
    
    @ViewBuilder private func SectionWithdrawView() -> some View {
        SafeListSectionHeader(text: "safe_zone.safe4.withdraw".localized)
        ListSection {
            ClickableRow(action: {
                guard let vc = WithdrawModule.viewController(type: .masterNode) else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: SafeWithdrawType.masterNode.title)
            }
            ClickableRow(action: {
                guard let vc = WithdrawModule.viewController(type: .superNode) else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: SafeWithdrawType.superNode.title)
            }
            ClickableRow(action: {
                guard let vc = WithdrawModule.viewController(type: .proposal) else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: SafeWithdrawType.proposal.title)
            }
            ClickableRow(action: {
                guard let vc = RewardsModule.viewController() else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "safe_zone.row.rewards".localized + "safe_zone.safe4.withdraw".localized)
            }
            ClickableRow(action: {
                guard let vc = WithdrawModule.viewController(type: .voteLocked) else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: SafeWithdrawType.voteLocked.title)
            }
        }
    }
    
    @ViewBuilder private func SectionSRC20View() -> some View {
        SafeListSectionHeader(text: "SRC20_Deploy_Title".localized)
        ListSection {
            ClickableRow(action: {
                guard let vc = DeployModule.viewController() else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "SRC20_Deploy_One_Click_Issu".localized)
            }
            ClickableRow(action: {
                guard let nav = navController else { return }
                guard let vc = SRC20ManagerModule.viewController(nav: nav) else { return }
                vc.hidesBottomBarWhenPushed = true
                navController?.pushViewController(vc, animated: true)
            }) {
                ItemView(title: "SRC20_Deploy_Promotion".localized)
            }
        }
    }
    
    @ViewBuilder private func SectionBasicInfoView() -> some View {
        SafeListSectionHeader(text: "safe_zone.section.basic".localized)
        ListSection {
            ClickableRow(action: {
                linkUrl = URL(string: "https://anwang.com")
            }) {
                ItemView(title: "safe_zone.row.homepage".localized)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://chain.anwang.com")
            }) {
                TagItemView(text:  "safe_zone.row.blockExplorer".localized(""), name: "SAFE", code: "SAFE3", type: .left)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://anwang.com/assetgate.html")
            }) {
                TagItemView(text: "safe_zone.row.acrossExplorer".localized(""), name: "SAFE", code: "SAFE3", type: .left)
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://safe4.anwang.com")
            }) {
                ItemView(title: "safe_zone.row.blockExplorer".localized("SAFE"))
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://safe4.anwang.com/crosschains")
            }) {
                ItemView(title: "safe_zone.row.acrossExplorer".localized("SAFE"))
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://www.coingecko.com/en/coins/safe")
            }) {
                ItemView(title: "SAFE@coingecko")
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://coinmarketcap.com/currencies/safe")
            }) {
                ItemView(title: "SAFE@coinmarketcap")
            }
            ClickableRow(action: {
                linkUrl = URL(string: "https://www.coingecko.com/en/coins/safe-anwang")
            }) {
                ItemView(title: "SAFE BEP20@CMC")
            }
        }
    }
    
    struct SafeListSectionHeader: View {
        let text: String

        var body: some View {
            Text(text.uppercased())
                .themeSubhead1(color: .themeLeah)
                .padding(EdgeInsets(top: .margin16, leading: 0, bottom: 0, trailing: 0))
        }
    }
    
    struct ItemView: View {
        let title: String

        var body: some View {
            Image("safe_logo_24").renderingMode(.original)
            Text(title).themeBody()
            Image.disclosureIcon
        }
    }
    
    struct TagItemView: View {
        let text: String
        let name: String
        let code: String
        let type: TagCoinPositionType
        
        var body: some View {
            Image("safe_logo_24").renderingMode(.original)
            switch type {
            case .left:
                TagCoinView(name: name, code: code)
                Text(text).themeBody()
            case .right:
                Text(text).themeBody().fixedSize()
                TagCoinView(name: name, code: code)
            }
            Spacer()
            Image.disclosureIcon
        }
        
        enum TagCoinPositionType {
        case left
        case right
        }
    }
    
    struct TagCoinView: View {
        let name: String
        var nameFont: Font? = .themeBody

        let code: String
        var codeFont: Font? = .themeMicro
        
        var body: some View {
            HStack() {
                Text(name)
                    .font(nameFont)
                    .foregroundColor(.themeLeah)
                    .fixedSize()
                
                Text(code)
                    .font(codeFont)
                    .foregroundColor(.themeLeah)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.themeLightGray.opacity(0.5))
                    )
                    .alignmentGuide(.leading) { _ in 0 }
                    .fixedSize()
            }
        }
    }
    
    enum PresentDestination: Hashable, Identifiable {
        case lineLockRecoard
        case crossChain(vc: UIViewController)
        case safeSwapScr20

        var id: Self {
            self
        }
    }
}

