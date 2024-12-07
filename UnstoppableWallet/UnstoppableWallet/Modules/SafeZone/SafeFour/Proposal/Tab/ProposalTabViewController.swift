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

class ProposalTabViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    
    private let tabsView = FilterView(buttonStyle: .tab)
    private let viewModel: ProposalTabViewModel
    private let privateKey: Data
    private let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    
    private var allViewController: ProposalViewController
    private var mineViewController: ProposalViewController
    
    init(viewModel: ProposalTabViewModel, privateKey: Data, evmKit: EvmKit.Kit) {
        self.viewModel = viewModel
        self.privateKey = privateKey
        allViewController = ProposalModule.subViewController(type: .All)
        mineViewController = ProposalModule.subViewController(type: .Mine(address: evmKit.receiveAddress.hex))
        
        super.init()
        
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.row.proposal".localized
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
    private func sync(currentTab: ProposalModule.Tab) {
        tabsView.select(index: currentTab.rawValue)
        setViewPager(tab: currentTab)
    }

    private func onSelectTab(index: Int) {
        guard let tab = ProposalModule.Tab(rawValue: index) else {
            return
        }

        viewModel.onSelect(tab: tab)
    }

    private func setViewPager(tab: ProposalModule.Tab) {
        pageViewController.setViewControllers([viewController(tab: tab)], direction: .forward, animated: false)
    }

    private func viewController(tab: ProposalModule.Tab) -> UIViewController {
        switch tab {
        case .all: return allViewController
        case .mine: return mineViewController
        }
    }
    
    @objc private func add() {
        guard viewModel.isEnabledAdd else {
            HudHelper.instance.show(banner: .error(string: "无法创建，需区块高度大于86400".localized))
            return
        }
        let vc = ProposalCreateModule.viewController(privateKey: privateKey)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension ProposalTabViewController: IPresentDelegate {

    func present(viewController: UIViewController) {
        navigationController?.present(viewController, animated: true)
    }

    func push(viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

}
