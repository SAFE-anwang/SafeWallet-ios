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
    private let viewModel: MainSafeZoneViewModel
    private let tableView = SectionsTableView(style: .grouped)

    init(viewModel: MainSafeZoneViewModel, urlManager: UrlManager) {
        self.viewModel = viewModel
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
    
    private func openSendSafe2eth(chainType: ChainType) {
        tableView.deselectCell(withCoordinator: transitionCoordinator, animated: true)
        if let module = Safe4Module.handlerSafe2eth(chainType: chainType) {
            present(module, animated: true)
        }
    }
    
    private func openSendEth2safe(chainType: ChainType) {
        tableView.deselectCell(withCoordinator: transitionCoordinator, animated: true)
        if let module = Safe4Module.handlerEth2safe(chainType: chainType) {
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
    
    private func buildSafe2EthCell(title: String, chainName: String, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
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
                component.text = "=>"
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
    
    private func buildEth2SafeCell(title: String, chainName: String, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
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
                component.text = "=>"
            },
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.setContentCompressionResistancePriority(.required, for: .horizontal)
                component.text = title
            },
            .margin8,
            .image20 { (component: ImageComponent) -> () in
                component.imageView.image = UIImage(named: "arrow_big_forward_20")
            }
        ]))
        return cell
    }
    
    private var crossChainETH_Rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildSafe2EthCell(title: "SAFE", chainName: "ERC20", backgroundStyle: .lawrence, isFirst: true),
                    id: "crossChainETH_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendSafe2eth(chainType: .ETH)
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "ERC20", backgroundStyle: .lawrence),
                    id: "crossChainETH_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendEth2safe(chainType: .ETH)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.contract".localized, backgroundStyle: .lawrence),
                    id: "crossChainETH_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://etherscan.io/token/0xEE9c1Ea4DCF0AAf4Ff2D78B6fF83AA69797B65Eb")

                    }
            ),
            StaticRow(
                    cell: buildTitleImage(title: "SAFE@uniswapv2", backgroundStyle: .lawrence, isLast: true),
                    id: "crossChainETH_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://v2.info.uniswap.org/pair/0x8b04fdc8e8d7ac6400b395eb3f8569af1496ee33")

                    }
            ),
            
        ]
    }
    
    private var crossChainBSC_Rows: [RowProtocol] {
        [
            StaticRow(
                    cell: buildSafe2EthCell(title: "SAFE", chainName: "BEP20", backgroundStyle: .lawrence, isFirst: true),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendSafe2eth(chainType: .BSC)
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "BEP20", backgroundStyle: .lawrence),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendEth2safe(chainType: .BSC)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.contract".localized, backgroundStyle: .lawrence),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://bscscan.com/token/0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1")

                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@pancakewap", backgroundStyle: .lawrence, isLast: true),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://pancakeswap.finance/info/pool/0x400db103af7a0403c9ab014b2b73702b89f6b4b7")
                    }
            ),
            
        ]
    }
    
    private var crossChainMatic_Rows: [RowProtocol] {
        [
            StaticRow(
                    cell: buildSafe2EthCell(title: "SAFE", chainName: "MATIC", backgroundStyle: .lawrence, isFirst: true),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendSafe2eth(chainType: .MATIC)
                    }
            ),
            StaticRow(
                cell: buildEth2SafeCell(title: "SAFE", chainName: "MATIC", backgroundStyle: .lawrence),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openSendEth2safe(chainType: .MATIC)
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.contract".localized, backgroundStyle: .lawrence),
                    id: "crossChainBSC_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://bscscan.com/token/0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779")

                    }
            ),
        ]
    }
    
    private var locked_Rows: [RowProtocol] {
        [
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.linear".localized, backgroundStyle: .lawrence, isFirst: true),
                    id: "locked_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.tableView.deselectCell(withCoordinator: self?.transitionCoordinator, animated: true)
                        if let module = Safe4Module.handlerLineLock() {
                            self?.present(module, animated: true)
                        }
                    }
            ),
            StaticRow(
                    cell: buildTitleImage(title: "safe_zone.row.lock".localized, backgroundStyle: .lawrence, isLast: true),
                    id: "locked_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openLineLockRecoard()
//                        // to do ..
//                        HudHelper.instance.show(banner: .attention(string: "safe_zone.Safe4_Coming_Soon".localized))
//                        self?.tableView.deselectCell(withCoordinator: self?.transitionCoordinator, animated: true)
                    }
            ),
        ]
    }
    
    private var basic_Rows: [RowProtocol] {
        [
            StaticRow(
                    cell: buildTitleImage(title: "safe_zone.row.homepage".localized, backgroundStyle: .lawrence, isFirst: true),
                    id: "basic_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://anwang.com")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.blockExplorer".localized, backgroundStyle: .lawrence),
                    id: "basic_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://chain.anwang.com")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "safe_zone.row.acrossExplorer".localized, backgroundStyle: .lawrence),
                    id: "basic_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://anwang.com/assetgate.html")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@coingecko", backgroundStyle: .lawrence),
                    id: "basic_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"//www.coingecko.com/en/coins/safe")
                    }
            ),
            StaticRow(
                cell: buildTitleImage(title: "SAFE@coinmarketcap", backgroundStyle: .lawrence),
                    id: "basic_Rows",
                    height: .heightCell48,
                    action: { [weak self] in
                        self?.openUrl(explorerUrl:"https://coinmarketcap.com/currencies/safe")
                    }
            ),
            
            StaticRow(
                    cell: buildTitleImage(title: "SAFE BEP20@CMC", backgroundStyle: .lawrence, isLast: true),
                    id: "basic_Rows",
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
            Section(id: "crossChainETH", headerState: .text(text: "safe_zone.section.cross_eth".localized, topMargin: 25, bottomMargin: 15), rows: crossChainETH_Rows),
            Section(id: "crossChainBSC", headerState: .text(text: "safe_zone.section.cross_bsc".localized, topMargin: 25, bottomMargin: 15), rows: crossChainBSC_Rows),
            Section(id: "crossChainMatic", headerState: .text(text: "safe_zone.section.cross_matic".localized, topMargin: 25, bottomMargin: 15), rows: crossChainMatic_Rows),
            Section(id: "Locked", headerState: .text(text: "safe_zone.section.locked".localized, topMargin: 25, bottomMargin: 15), rows: locked_Rows),
            Section(id: "Basic", headerState: .text(text: "safe_zone.section.basic".localized, topMargin: 25, bottomMargin: 15), rows: basic_Rows),
        ]
    }

}

