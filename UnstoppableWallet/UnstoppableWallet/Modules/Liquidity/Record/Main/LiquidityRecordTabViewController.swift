import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit

class LiquidityRecordTabViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    
    private let tabsView = FilterView(buttonStyle: .tab)
    private let viewModel: LiquidityRecordTabViewModel
    private let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    
    private var bscViewController: LiquidityRecordViewController
    private var ethViewController: LiquidityRecordViewController
    
    init?(viewModel: LiquidityRecordTabViewModel) {
        self.viewModel = viewModel
        
        bscViewController = LiquidityRecordModule.subViewController(dexType: .pancakeSwap, blockchainType: .binanceSmartChain)
        ethViewController = LiquidityRecordModule.subViewController(dexType: .uniswap, blockchainType: .ethereum)
        
        super.init()
        
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "liquidity.title.record".localized
        navigationItem.backBarButtonItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
        
        view.addSubview(tabsView)
        tabsView.snp.makeConstraints { maker in
            maker.top.equalTo(view.safeAreaLayoutGuide)
            maker.leading.trailing.equalToSuperview()
            maker.height.equalTo(FilterView.height)
        }

        view.addSubview(pageViewController.view)
        pageViewController.view.snp.makeConstraints { maker in
            maker.top.equalTo(tabsView.snp.bottom)
            maker.leading.trailing.equalToSuperview()
            maker.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }

        tabsView.reload(filters: viewModel.tabs.map {
            FilterView.ViewItem.item(title: $0.title)
        })

        tabsView.onSelect = { [weak self] index in
            self?.onSelectTab(index: index)
        }
        subscribe(disposeBag, viewModel.currentTabDriver) { [weak self] in self?.sync(currentTab: $0) }
        
        bscViewController.parentNavigationController = navigationController
        ethViewController.parentNavigationController = navigationController
        
    }
    private func sync(currentTab: LiquidityRecordModule.Tab) {
        tabsView.select(index: currentTab.rawValue)
        setViewPager(tab: currentTab)
    }

    private func onSelectTab(index: Int) {
        guard let tab = LiquidityRecordModule.Tab(rawValue: index) else {
            return
        }

        viewModel.onSelect(tab: tab)
    }

    private func setViewPager(tab: LiquidityRecordModule.Tab) {
        pageViewController.setViewControllers([viewController(tab: tab)], direction: .forward, animated: false)
    }

    private func viewController(tab: LiquidityRecordModule.Tab) -> UIViewController {
        switch tab {
        case .bsc: return bscViewController
        case .eth: return ethViewController
        }
    }
}

extension LiquidityRecordTabViewController: IPresentDelegate {

    func present(viewController: UIViewController) {
        navigationController?.present(viewController, animated: true)
    }

    func push(viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

}
