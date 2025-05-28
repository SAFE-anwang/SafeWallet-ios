

import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import SafariServices
import ComponentKit
import MarketKit

class MainSafeZoneViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private var urlManager: UrlManager
    private let tableView = SectionsTableView(style: .grouped)

    init(urlManager: UrlManager) {
        self.urlManager = urlManager
        super.init()

        tabBarItem = UITabBarItem(title: "safe_zone.nav.title".localized, image: UIImage(named: "filled_settings_2_24"), tag: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.nav.title".localized
        navigationItem.backBarButtonItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)

        tableView.sectionDataSource = self

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.buildSections()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        tableView.deselectCell(withCoordinator: transitionCoordinator, animated: animated)
    }
    
    private func openSendCrossChain(wsafeType: WSafeChainType, crossChainType: CrossChainType, isSafe4: Bool) {
        tableView.deselectCell(withCoordinator: transitionCoordinator, animated: true)
        if let module = Safe4Module.handlerCrossChain(wsafeType: wsafeType, crossChainType: crossChainType, isSafe4: isSafe4) {
            present(module, animated: true)
        }
    }

    
    private func openUrl(explorerUrl: String) {
        tableView.deselectCell(withCoordinator: transitionCoordinator, animated: true)
        urlManager.open(url: explorerUrl, from: navigationController)

    }
    private func openLineLockRecoard() {
        tableView.deselectCell(withCoordinator: transitionCoordinator, animated: true)
        if let module = LineLockRecoardModule.viewController() {
            navigationController?.pushViewController(module, animated: true)
        }

    }
    
    private func buildTitleImage(title: String, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .image24 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "safelog")
            },
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.text = title
            },
            .margin8,
            .image20 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "arrow_big_forward_20")
            }
        ]))
        return cell
    }
    
    private func buildSafe2EthCell(title: String, chainName: String, separate: String = "=>", backgroundStyle: BaseSelectableThemeCell.BackgroundStyle, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .image24 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "safelog")
            },
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = title
            },
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = separate
            },
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = title
            },
            .margin4,
            .badge{ (component: BadgeComponent) -> () in
                component.badgeView.set(style: .small)
                component.badgeView.textColor = .themeBran
                component.badgeView.font = .microSB
                component.badgeView.text = chainName
            },
            .text { (component: TextComponent) -> () in
            },
            .margin8,
            .image20 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "arrow_big_forward_20")
            }
        ]))
        return cell
    }
    
    private func buildEth2SafeCell(title: String, chainName: String, separate: String = "=>", content: String? = nil, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .image24 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "safelog")
            },
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = title
            },
            .margin4,
            .badge{ (component: BadgeComponent) -> () in
                component.badgeView.set(style: .small)
                component.badgeView.textColor = .themeBran
                component.badgeView.font = .microSB
                component.badgeView.text = chainName
            },
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = separate
            },
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentCompressionResistancePriority(.required, for: .horizontal)
                component.text = content ?? title
            },
            .margin8,
            .image20 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "arrow_big_forward_20")
            }
        ]))
        return cell
    }
        
    private var locked_Rows: [RowProtocol] {
        [
//            StaticRow(
//                cell: buildTitleImage(title: "safe_zone.row.linear".localized, backgroundStyle: .lawrence, isFirst: true),
//                    id: "locked_Rows",
//                    height: .heightCell48,
//                    action: { [weak self] in
//                        self?.tableView.deselectCell(withCoordinator: self?.transitionCoordinator, animated: true)
//                        if let module = Safe4Module.handlerLineLock() {
//                            self?.present(module, animated: true)
//                        }
//                    }
//            ),
//            buildEth2SafeCell(title: "SAFE", chainName: "SAFE3", separate: "", content: "safe_zone.row.lock".localized,
            StaticRow(
                    cell: buildEth2SafeCell(title: "SAFE", chainName: "SAFE3", separate: "", content: "safe_zone.row.lock".localized, backgroundStyle: .lawrence, isFirst: true, isLast: true),
                    id: "locked_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openLineLockRecoard()
                    }
            ),
        ]
    }
    
    private var safe4_Rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.superNode".localized, backgroundStyle: .lawrence, isFirst: true),
                    id: "superNode_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = SuperNodeModule.viewController() else{ return }
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.masterNode".localized, backgroundStyle: .lawrence),
                    id: "masterNode_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = MasterNodeModule.viewController() else{ return }
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.proposal".localized, backgroundStyle: .lawrence),
                    id: "proposal_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = ProposalModule.viewController() else { return }
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
//            StaticRow(
//                cell: buildTitleImage(title: "safe_zone.row.rewards".localized, backgroundStyle: .lawrence),
//                    id: "rewards_Rows",
//                    height: .heightCell48,
//                    action: { [weak self] in
////                        guard let vc = RewardsModule.viewController() else { return }
////                        self?.navigationController?.pushViewController(vc, animated: true)
//                        guard let vc = RewardsModule.viewController() else { return }
//                        vc.hidesBottomBarWhenPushed = true
//                        self?.navigationController?.pushViewController(vc, animated: true)
//
//                    }
//            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "SAFE3", backgroundStyle: .lawrence),
                    id: "redeem_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = RedeemSafe3Module.viewController() else { return }
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE领取".localized, backgroundStyle: .lawrence, isLast: true),
                    id: "draw_safe4_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = DrawSafe4Module.viewController() else { return }
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            )

        ]
    }
    
    private var basic_Rows: [RowProtocol] {
        [
            StaticRow(
                    cell: buildTitleImage(title: "safe_zone.row.homepage".localized, backgroundStyle: .lawrence, isFirst: true),
                    id: "basic_Rows_0",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://anwang.com")
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "SAFE3", separate: "", content: "safe_zone.row.blockExplorer".localized(""), backgroundStyle: .lawrence) ,
                    id: "basic_Rows_1",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://chain.anwang.com")
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "SAFE3", separate: "", content: "safe_zone.row.acrossExplorer".localized(""), backgroundStyle: .lawrence),
                    id: "basic_Rows_2",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://anwang.com/assetgate.html")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.blockExplorer".localized("SAFE"), backgroundStyle: .lawrence),
                    id: "basic_Rows_3",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://safe4.anwang.com")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.acrossExplorer".localized("SAFE"), backgroundStyle: .lawrence),
                    id: "basic_Rows_4",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://safe4.anwang.com/crosschains")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@coingecko", backgroundStyle: .lawrence),
                    id: "basic_Rows_5",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"//www.coingecko.com/en/coins/safe")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@coinmarketcap", backgroundStyle: .lawrence),
                    id: "basic_Rows_6",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://coinmarketcap.com/currencies/safe")
                    }
            ),
            
            StaticRow(
                    cell: buildTitleImage(title: "SAFE BEP20@CMC", backgroundStyle: .lawrence, isLast: true),
                    id: "basic_Rows_7",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://www.coingecko.com/en/coins/safe-anwang")
                    }
            ),
        ]
    }

}
extension MainSafeZoneViewController: SectionsDataSource {

    func buildSections() -> [SectionProtocol] {
        [
            Section(id: "Locked", headerState: .text(text: "safe_zone.section.locked".localized, topMargin: 25, bottomMargin: 15), rows: locked_Rows),
            Section(id: "Safe", headerState: .text(text: "safe_zone.section.safe4".localized, topMargin: 25, bottomMargin: 15), rows: safe4_Rows),
            Section(id: "safe4CrossChainETH", headerState: .text(text: "safe_zone.section.cross_eth".localized, topMargin: 25, bottomMargin: 15), rows: safe4CrossChainETH_Rows),
            Section(id: "safe4CrossChainBSC", headerState: .text(text: "safe_zone.section.cross_bsc".localized, topMargin: 25, bottomMargin: 15), rows: safe4CrossChainBSC_Rows),
            Section(id: "safe4CrossChainMatic", headerState: .text(text: "safe_zone.section.cross_matic".localized, topMargin: 25, bottomMargin: 15), rows: safe4CrossChainMatic_Rows),
            Section(id: "safe4SwapSrc", headerState: .text(text: "safe_zone.section.safe4SwapSrc".localized, topMargin: 25, bottomMargin: 15), rows: safe4SwapSrc_Rows),
            Section(id: "withdraw", headerState: .text(text: "safe_zone.safe4.withdraw".localized, topMargin: 25, bottomMargin: 15), rows: safe4Withdraw_Rows),
            Section(id: "Basic", headerState: .text(text: "safe_zone.section.basic".localized, topMargin: 25, bottomMargin: 15), rows: basic_Rows),
        ]
    }
}

// safe4 Withdraw
extension MainSafeZoneViewController {
    private var safe4Withdraw_Rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildTitleImage(title: SafeWithdrawType.masterNode.title, backgroundStyle: .lawrence, isFirst: true),
                    id: "withdraw_Rows_0",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = WithdrawModule.viewController(type: .masterNode) else { return }
                        vc.hidesBottomBarWhenPushed = true
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: SafeWithdrawType.superNode.title, backgroundStyle: .lawrence),
                    id: "withdraw_Rows_1",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = WithdrawModule.viewController(type: .superNode) else { return }
                        vc.hidesBottomBarWhenPushed = true
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
//            StaticRow(
//                cell: buildTitleImage(title: SafeWithdrawType.proposal.title, backgroundStyle: .lawrence),
//                    id: "withdraw_Rows_2",
//                    height: .heightCell48,
//                    action: { [weak self] in
//                        guard let vc = WithdrawModule.viewController(type: .proposal) else { return }
//                        vc.hidesBottomBarWhenPushed = true
//                        self?.navigationController?.pushViewController(vc, animated: true)
//                    }
//            ),
            StaticRow(
                    cell: buildTitleImage(title: "safe_zone.row.rewards".localized + "safe_zone.safe4.withdraw".localized, backgroundStyle: .lawrence),
                    id: "withdraw_Rows_3",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = RewardsModule.viewController() else { return }
                        vc.hidesBottomBarWhenPushed = true
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: SafeWithdrawType.voteLocked.title, backgroundStyle: .lawrence, isLast: true),
                    id: "withdraw_Rows_4",
                    height: .heightCell48,
                    action: { [weak self] in
                        guard let vc = WithdrawModule.viewController(type: .voteLocked) else { return }
                        vc.hidesBottomBarWhenPushed = true
                        self?.navigationController?.pushViewController(vc, animated: true)
                    }
            )
        ]
    }
}

// safe4 Cross Chain
extension MainSafeZoneViewController {
    private var safe4CrossChainETH_Rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildSafe2EthCell(title: "SAFE", chainName: "ERC20", backgroundStyle: .lawrence, isFirst: true),
                    id: "safe4crossChainETH_Rows_0",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendCrossChain(wsafeType: .ETH, crossChainType: .safeCrossToWSafe, isSafe4: true)
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "ERC20", backgroundStyle: .lawrence),
                    id: "safe4crossChainETH_Rows_1",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendCrossChain(wsafeType: .ETH, crossChainType: .wsafeCrossToSafe, isSafe4: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.contract".localized, backgroundStyle: .lawrence),
                    id: "safe4crossChainETH_Rows_2",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://etherscan.io/token/0xEE9c1Ea4DCF0AAf4Ff2D78B6fF83AA69797B65Eb")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@uniswapv2", backgroundStyle: .lawrence, isLast: true),
                    id: "safe4crossChainMATIC_Rows_2",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://v2.info.uniswap.org/pair/0x8b04fdc8e8d7ac6400b395eb3f8569af1496ee33")


                    }
            ),
        ]
    }
    
    private var safe4CrossChainBSC_Rows: [RowProtocol] {
        [
            StaticRow(
                    cell: buildSafe2EthCell(title: "SAFE", chainName: "BEP20", backgroundStyle: .lawrence, isFirst: true),
                    id: "safe4crossChainBSC_Rows_0",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendCrossChain(wsafeType: .BSC, crossChainType: .safeCrossToWSafe, isSafe4: true)
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "BEP20", backgroundStyle: .lawrence),
                    id: "safe4crossChainBSC_Rows_1",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendCrossChain(wsafeType: .BSC, crossChainType: .wsafeCrossToSafe, isSafe4: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.contract".localized, backgroundStyle: .lawrence),
                    id: "safe4crossChainBSC_Rows_2",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://bscscan.com/token/0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@pancakeswap", backgroundStyle: .lawrence, isLast: true),
                    id: "safe4crossChainBSC_Rows_2",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://pancakeswap.finance/info/pool/0x400db103af7a0403c9ab014b2b73702b89f6b4b7")
                    }
            )
        ]
    }
    
    private var safe4CrossChainMatic_Rows: [RowProtocol] {
        [
            StaticRow(
                    cell: buildSafe2EthCell(title: "SAFE", chainName: "MATIC", backgroundStyle: .lawrence, isFirst: true),
                    id: "safe4crossChainMATIC_Rows_0",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendCrossChain(wsafeType: .MATIC, crossChainType: .safeCrossToWSafe, isSafe4: true)
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "MATIC", backgroundStyle: .lawrence),
                    id: "safe4crossChainMATIC_Rows_1",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendCrossChain(wsafeType: .MATIC, crossChainType: .wsafeCrossToSafe, isSafe4: true)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.contract".localized, backgroundStyle: .lawrence, isLast: true),
                    id: "safe4crossChainMATIC_Rows_2",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://polygonscan.com/address/0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779")
                    }
            )
        ]
    }
    
    private var safe4SwapSrc_Rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildSafe2EthCell(title: "SAFE", chainName: "SCR20", separate: "<=>", backgroundStyle: .lawrence, isFirst: true, isLast: true),
                    id: "safe4SwapSrc_Row",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.tableView.deselectCell(withCoordinator: self?.transitionCoordinator, animated: true)
                        guard let vc = Safe4SwapModule.viewController() else { return }
                        self?.navigationController?.present(vc, animated: true)
                    }
            )
        ]
    }
}
