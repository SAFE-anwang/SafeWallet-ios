import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit
import EvmKit

class RedeemSafe3TabViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    
    private let tabsView = FilterView(buttonStyle: .tab)
    private let viewModel: RedeemSafe3TabViewModel
    private let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    
    private var localViewController: RedeemSafe3ViewController
    private var otherViewController: RedeemSafe3ViewController
    
    init(account: Account, viewModel: RedeemSafe3TabViewModel, safe4EvmKitWrapper: EvmKitWrapper) {
        self.viewModel = viewModel
        localViewController = RedeemSafe3Module.subViewController(account: account, safe4EvmKitWrapper: safe4EvmKitWrapper, type: .local)
        otherViewController = RedeemSafe3Module.subViewController(account: account, safe4EvmKitWrapper: safe4EvmKitWrapper, type: .other)
        
        super.init()
        
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SAFE3 -> SAFE4".localized
        navigationItem.largeTitleDisplayMode = .never
        
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
        
        localViewController.parentNavigationController = navigationController
        otherViewController.parentNavigationController = navigationController
        
    }
    private func sync(currentTab: RedeemSafe3Module.Tab) {
        tabsView.select(index: currentTab.rawValue)
        setViewPager(tab: currentTab)
    }

    private func onSelectTab(index: Int) {
        guard let tab = RedeemSafe3Module.Tab(rawValue: index) else {
            return
        }

        viewModel.onSelect(tab: tab)
    }

    private func setViewPager(tab: RedeemSafe3Module.Tab) {
        pageViewController.setViewControllers([viewController(tab: tab)], direction: .forward, animated: false)
    }

    private func viewController(tab: RedeemSafe3Module.Tab) -> UIViewController {
        switch tab {
        case .other: return otherViewController  
        case .local: return localViewController
        }
    }
}

extension RedeemSafe3TabViewController: IPresentDelegate {

    func present(viewController: UIViewController) {
        navigationController?.present(viewController, animated: true)
    }

    func push(viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

}
