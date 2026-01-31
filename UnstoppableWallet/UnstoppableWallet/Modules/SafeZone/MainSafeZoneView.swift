import Kingfisher
import SwiftUI
import UIExtensions
import SafariServices
import MarketKit
import Combine

struct MainSafeZoneView: View {
    private let viewModel = MainSafeZoneViewModel()
    
    var body: some View {
        ScrollableThemeView {
            VStack(spacing: .margin8) {
                SectionLockView()
                SectionSafe3LockView()
                SectionNodeView()
                SectionCrossETHView()
                SectionCrossBSCView()
                SectionCrossMATICView()
                SectionUsdtCrossETHView()
                SectionUsdtCrossBSCView()
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
                TagItemView(fromCoin: "SAFE", fromChain: "SAFE3", toCoin: "SAFE", toChain: nil)
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
        SafeListSectionHeader(text: "SAFE" + "safe_zone.section.cross_eth".localized)
        ListSection {
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4Native()?.eth?.safe2eth == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放".localized))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .SAFE(chain: .ETH, direction: .SAFE_CrossChain_to_other)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            })
            {
                TagItemView(fromCoin: "SAFE", fromChain: nil, toCoin: "SAFE", toChain: "ERC20")
            }
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4Native()?.eth?.eth2safe == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放".localized))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .SAFE(chain: .ETH, direction: .other_CrossChain_to_SAFE)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: "ERC20", toCoin: "SAFE", toChain: nil)
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
        SafeListSectionHeader(text: "SAFE" + "safe_zone.section.cross_bsc".localized)
        ListSection {
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4Native()?.bsc?.safe2bsc == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放"))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .SAFE(chain: .BSC, direction: .SAFE_CrossChain_to_other)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: nil, toCoin: "SAFE", toChain: "BEP20")
            }
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4Native()?.bsc?.bsc2safe == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放".localized))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .SAFE(chain: .BSC, direction: .other_CrossChain_to_SAFE)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: "BEP20", toCoin: "SAFE", toChain: nil)
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
        SafeListSectionHeader(text: "SAFE" + "safe_zone.section.cross_matic".localized)
        ListSection {
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4Native()?.matic?.safe2matic == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放".localized))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .SAFE(chain: .POL, direction: .SAFE_CrossChain_to_other)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: nil, toCoin: "SAFE", toChain: "MATIC")
            }
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4Native()?.matic?.matic2safe == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放"))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .SAFE(chain: .POL, direction: .other_CrossChain_to_SAFE)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: "MATIC", toCoin: "SAFE", toChain: nil)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://polygonscan.com/address/0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
        }

    }
    
    @ViewBuilder private func SectionUsdtCrossETHView() -> some View {
        SafeListSectionHeader(text: "USDT" + "safe_zone.section.cross_eth".localized)
        ListSection {
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4USDT()?.eth?.safe2eth == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放"))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .USDT(chain: .ETH, direction: .SAFE_CrossChain_to_other)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            })
            {
                TagItemView(fromCoin: "USDT", fromChain: "SAFE", toCoin: "USDT", toChain: "ETH")
            }
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4USDT()?.eth?.eth2safe == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放"))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .USDT(chain: .ETH, direction: .other_CrossChain_to_SAFE)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "USDT", fromChain: "ETH", toCoin: "USDT", toChain: "SAFE")
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://safe4.anwang.com/address/0x9C1246a4BB3c57303587e594a82632c3171662C9")
                Coordinator.shared.present(url: linkUrl)
            }) {
                ItemView(title: "safe_zone.row.contract".localized)
            }
        }
    }
    
    @ViewBuilder private func SectionUsdtCrossBSCView() -> some View {
        SafeListSectionHeader(text: "USDT" + "safe_zone.section.cross_bsc".localized)
        ListSection {
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4USDT()?.bsc?.safe2bsc == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放"))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .USDT(chain: .BSC, direction: .SAFE_CrossChain_to_other)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "USDT", fromChain: "SAFE", toCoin: "USDT", toChain: "BSC")
            }
            ClickableRow(action: {
                if viewModel.crossChainManager.getSafe4USDT()?.bsc?.bsc2safe == false {
                    HudHelper.instance.show(banner: .error(string: "功能未开放"))
                    return
                }
                if let viewModel = CrossChainModule.crossChainViewModel(token: .USDT(chain: .BSC, direction: .other_CrossChain_to_SAFE)) {
                    Coordinator.shared.present { _ in
                        ThemeNavigationStack {
                            CrossPreSendView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "USDT", fromChain: "BSC", toCoin: "USDT", toChain: "SAFE")
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://safe4.anwang.com/address/0x9C1246a4BB3c57303587e594a82632c3171662C9")
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
                        ThemeNavigationStack {
                            Safe4SwapView(viewModel: viewModel)
                        }
                    }
                }
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: nil, separator: "<=>", toCoin: "SAFE", toChain: "SRC20")
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
                TagItemView(fromCoin: "SAFE", fromChain: "SAFE3", separator: "", toCoin: "safe_zone.row.blockExplorer".localized(""), toChain: nil)
            }
            ClickableRow(action: {
                let linkUrl = URL(string: "https://anwang.com/assetgate.html")
                Coordinator.shared.present(url: linkUrl)
            }) {
                TagItemView(fromCoin: "SAFE", fromChain: "SAFE3", separator: "", toCoin: "safe_zone.row.acrossExplorer".localized(""), toChain: nil)
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
        let fromCoin: String
        let fromChain: String?
        var separator: String = "=>"
        let toCoin: String
        let toChain: String?
        
        var body: some View {
            Image("safe_logo_24").renderingMode(.original)
            
            if let fromChain {
                TagCoinView(name: fromCoin, code: fromChain)
            }else {
                Text(fromCoin)
                    .themeBody()
                    .fixedSize()
            }
            
            if separator.count > 0 {
                Text(separator)
                    .themeBody()
                    .fixedSize()
            }
            
            if let toChain {
                TagCoinView(name: toCoin, code: toChain)
            }else {
                Text(toCoin)
                    .themeBody()
                    .fixedSize()
            }
            
            Spacer()
            Image.disclosureIcon
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

