import Kingfisher
import SwiftUI
import UIExtensions
import SafariServices
import MarketKit
import Combine

struct MainSafeZoneView: View {

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
            .padding(EdgeInsets(top: .margin2, leading: .margin16, bottom: .margin32, trailing: .margin16))
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("safe_zone.nav.title".localized)
    }

    @ViewBuilder private func SectionLockView() -> some View {
        SafeListSectionHeader(text: "SAFE")
        ListSection {
            ClickableRow(action: {
                guard let vm = SafeLineLockModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    SafeLineLockView(viewModel: vm)
                }
            }) {
                ItemView(title: "safe_zone.row.linear".localized)
            }
            ClickableRow(action: {
                guard let vm = SafeLineLockRecoardModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    SafeLineLockRecoardView(viewModel: vm)
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
                guard let viewModel = LineLockRecoardModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    LineLockRecoardView(viewModel: viewModel)
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
                guard let viewModel = SuperNodeModule.tabViewModel() else{ return }
                Coordinator.shared.present { _ in
                    SuperNodeTabView(viewModel: viewModel)
                        .ignoresSafeArea()
                }
            }) {
                ItemView(title: "safe_zone.row.superNode".localized)
            }
            ClickableRow(action: {
                guard let viewModel = MasterNodeModule.tabViewModel() else{ return }
                Coordinator.shared.present { _ in
                    MasterNodeTabView(viewModel: viewModel)
                        .ignoresSafeArea()
                }
            }) {
                ItemView(title: "safe_zone.row.masterNode".localized)
            }
            ClickableRow(action: {
                guard let viewModel = ProposalModule.tabViewModel() else { return }
                Coordinator.shared.present { _ in
                    ProposalTabView(viewModel: viewModel)
                        .ignoresSafeArea()
                }
            }) {
                ItemView(title: "safe_zone.row.proposal".localized)
            }
            ClickableRow(action: {
                guard let vm = LockedRecordModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    LockedRecordView(viewModel: vm)
                        .ignoresSafeArea()
                }
            }) {
                ItemView(title: "safe_zone.safe4.account.lock".localized)
            }
            ClickableRow(action: {
                guard let viewModel = RedeemSafe3Module.tabViewModel() else { return }
                Coordinator.shared.present { _ in
                    RedeemSafe3TabView(viewModel: viewModel).ignoresSafeArea()
                }
            }) {
                TagItemView(text: "=> SAFE", name: "SAFE", code: "SAFE3", type: .left)
            }
            ClickableRow(action: {
                guard let viewModel = DrawSafe4Module.viewModel() else { return }
                Coordinator.shared.present { _ in
                    DrawSafe4View(viewModel: viewModel)
                        .ignoresSafeArea()
                }
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
                    Coordinator.shared.present { _ in
                        Safe4CrossChainView(viewController: vc)
                    }
                }
            })
            {
                TagItemView(text:  "SAFE =>", name: "SAFE", code: "ERC20", type: .right)
            }
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .ETH, crossChainType: .wsafeCrossToSafe, isSafe4: true) {
                    Coordinator.shared.present { _ in
                        Safe4CrossChainView(viewController: vc)
                    }
                }
            }) {
                TagItemView(text:  "=> SAFE", name: "SAFE", code: "ERC20", type: .left)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://etherscan.io/token/0xEE9c1Ea4DCF0AAf4Ff2D78B6fF83AA69797B65Eb")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://v2.info.uniswap.org/pair/0x8b04fdc8e8d7ac6400b395eb3f8569af1496ee33")
                Coordinator.shared.present(url: linkUrl)
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
                    Coordinator.shared.present { _ in
                        Safe4CrossChainView(viewController: vc)
                    }
                }
            }) {
                TagItemView(text:  "SAFE =>", name: "SAFE", code: "BEP20", type: .right)
            }
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .BSC, crossChainType: .wsafeCrossToSafe, isSafe4: true) {
                    Coordinator.shared.present { _ in
                        Safe4CrossChainView(viewController: vc)
                    }
                }
            }) {
                TagItemView(text:  "=> SAFE", name: "SAFE", code: "BEP20", type: .left)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://bscscan.com/token/0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://pancakeswap.finance/info/pool/0x400db103af7a0403c9ab014b2b73702b89f6b4b7")
                Coordinator.shared.present(url: linkUrl)
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
                    Coordinator.shared.present { _ in
                        Safe4CrossChainView(viewController: vc)
                    }
                }
            }) {
                TagItemView(text:  "SAFE =>", name: "SAFE", code: "MATIC", type: .right)
            }
            ClickableRow(action: {
                if let vc = Safe4Module.handlerCrossChain(wsafeType: .MATIC, crossChainType: .wsafeCrossToSafe, isSafe4: true) {
                    Coordinator.shared.present { _ in
                        Safe4CrossChainView(viewController: vc)
                    }
                }
            }) {
                TagItemView(text:  "=> SAFE", name: "SAFE", code: "MATIC", type: .left)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://polygonscan.com/address/0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779")
                Coordinator.shared.present(url: linkUrl)
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
                if let viewModel = Safe4SwapModule.viewModel() {
                    Coordinator.shared.present { _ in
                        Safe4SwapView(viewModel: viewModel)
                    }
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
                guard let vm = WithdrawModule.viewModel(type: .masterNode) else { return }
                Coordinator.shared.present { _ in
                    WithdrawView(viewModel: vm)
                }
            }) {
                ItemView(title: SafeWithdrawType.masterNode.title)
            }
            ClickableRow(action: {
                guard let vm = WithdrawModule.viewModel(type: .superNode) else { return }
                Coordinator.shared.present { _ in
                    WithdrawView(viewModel: vm)
                }
            }) {
                ItemView(title: SafeWithdrawType.superNode.title)
            }
            ClickableRow(action: {
                guard let vm = WithdrawModule.viewModel(type: .proposal) else { return }
                Coordinator.shared.present { _ in
                    WithdrawView(viewModel: vm)
                }
            }) {
                ItemView(title: SafeWithdrawType.proposal.title)
            }
            ClickableRow(action: {
                guard let viewModel = RewardsModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    RewardsView(viewModel: viewModel).ignoresSafeArea()
                }
            }) {
                ItemView(title: "safe_zone.row.rewards".localized + "safe_zone.safe4.withdraw".localized)
            }
            ClickableRow(action: {
                guard let vm = WithdrawModule.viewModel(type: .voteLocked) else { return }
                Coordinator.shared.present { _ in
                    WithdrawView(viewModel: vm)
                }
            }) {
                ItemView(title: SafeWithdrawType.voteLocked.title)
            }
        }
    }
    
    @ViewBuilder private func SectionSRC20View() -> some View {
        SafeListSectionHeader(text: "SRC20_Deploy_Title".localized)
        ListSection {
            ClickableRow(action: {
                guard let viewModel = DeployModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    DeployView(viewModel: viewModel)
                }
            }) {
                ItemView(title: "SRC20_Deploy_One_Click_Issu".localized)
            }
            ClickableRow(action: {
                guard let viewModel = SRC20ManagerModule.viewModel() else { return }
                Coordinator.shared.present { _ in
                    SRC20ManagerView(viewModel: viewModel)
                }
            }) {
                ItemView(title: "SRC20_Deploy_Promotion".localized)
            }
        }
    }
    
    @ViewBuilder private func SectionBasicInfoView() -> some View {
        SafeListSectionHeader(text: "safe_zone.section.basic".localized)
        ListSection {
            ClickableRow(action: {
                let linkUrl = URL(string: "https://anwang.com")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.homepage".localized)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://chain.anwang.com")
                Coordinator.shared.present(url: linkUrl)
            }) {
                TagItemView(text:  "safe_zone.row.blockExplorer".localized(""), name: "SAFE", code: "SAFE3", type: .left)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://anwang.com/assetgate.html")
                Coordinator.shared.present(url: linkUrl)
            }) {
                TagItemView(text: "safe_zone.row.acrossExplorer".localized(""), name: "SAFE", code: "SAFE3", type: .left)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://safe4.anwang.com")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.blockExplorer".localized("SAFE"))
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://safe4.anwang.com/crosschains")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.acrossExplorer".localized("SAFE"))
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://www.coingecko.com/en/coins/safe")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "SAFE@coingecko")
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://coinmarketcap.com/currencies/safe")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "SAFE@coinmarketcap")
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://www.coingecko.com/en/coins/safe-anwang")
                Coordinator.shared.present(url: linkUrl)
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
        case crossChain(vc: UIViewController)
        case safeSwapScr20

        var id: Self {
            self
        }
    }
}

