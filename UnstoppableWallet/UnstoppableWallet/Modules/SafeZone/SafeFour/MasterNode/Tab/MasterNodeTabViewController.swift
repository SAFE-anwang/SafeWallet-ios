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

class MasterNodeTabViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    
    private let tabsView = FilterView(buttonStyle: .tab)
    private let viewModel: MasterNodeTabViewModel
    private let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    
    private var allViewController: MasterNodeViewController
    private var mineViewController: MasterNodeViewController
    
    init(viewModel: MasterNodeTabViewModel, evmKit: EvmKit.Kit) {
        self.viewModel = viewModel
        allViewController = MasterNodeModule.subViewController(type: .All, evmKit: evmKit)
        mineViewController = MasterNodeModule.subViewController(type: .Mine, evmKit: evmKit)
        
        super.init()
        
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.row.masterNode".localized
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "safe4_add_2_24"), style: .plain, target: self, action: #selector(add))
        
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
        
        allViewController.parentNavigationController = navigationController
        mineViewController.parentNavigationController = navigationController
        
    }
    private func sync(currentTab: MasterNodeModule.Tab) {
        tabsView.select(index: currentTab.rawValue)
        setViewPager(tab: currentTab)
    }

    private func onSelectTab(index: Int) {
        guard let tab = MasterNodeModule.Tab(rawValue: index) else {
            return
        }

        viewModel.onSelect(tab: tab)
    }

    private func setViewPager(tab: MasterNodeModule.Tab) {
        pageViewController.setViewControllers([viewController(tab: tab)], direction: .forward, animated: false)
    }

    private func viewController(tab: MasterNodeModule.Tab) -> UIViewController {
        switch tab {
        case .all: return allViewController
        case .mine: return mineViewController
        }
    }
    @objc private func add() {
        switch viewModel.nodeType {
        case .masterNode:
            HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.node.tips.state.master".localized))
        case .superNode:
            HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.node.tips.state.super".localized))
        case .normal:
            guard let vc = MasterNodeRegisterModule.viewController() else {return }
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension MasterNodeTabViewController: IPresentDelegate {

    func present(viewController: UIViewController) {
        navigationController?.present(viewController, animated: true)
    }

    func push(viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

}

