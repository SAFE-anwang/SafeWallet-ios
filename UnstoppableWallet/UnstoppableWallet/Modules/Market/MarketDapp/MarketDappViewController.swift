import UIKit
import RxSwift
import ThemeKit
import SectionsTableView
import ComponentKit
import HUD

class MarketDappViewController: ThemeViewController {
    private let viewModel: MarketDappViewModel
    private let disposeBag = DisposeBag()
    
    private let linkButton = UIButton()
    private let tabsView = FilterView(buttonStyle: .tab)
    private let pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)

    weak var parentNavigationController: UINavigationController?
    
    private let allMarketDappListViewController: MarketDappListViewController
    private let ethMarketDappListViewController: MarketDappListViewController
    private let bscMarketDappListViewController: MarketDappListViewController
    private let safeMarketDappListViewController: MarketDappListViewController

    init(viewModel: MarketDappViewModel) {
        self.viewModel = viewModel
        
        allMarketDappListViewController = MarketDappModule.subViewController(tab: .ALL)
        ethMarketDappListViewController = MarketDappModule.subViewController(tab: .ETH)
        bscMarketDappListViewController = MarketDappModule.subViewController(tab: .BSC)
        safeMarketDappListViewController = MarketDappModule.subViewController(tab: .SAFE)
        
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        linkButton.cornerRadius = 8
        linkButton.setBackgroundColor(.white, for: .normal)
        linkButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        linkButton.titleLabel?.textAlignment = .left
        linkButton.contentHorizontalAlignment = .left
        linkButton.setTitle("safe_dapp.input".localized, for: .normal)
        linkButton.setTitleColor(.themeDark, for: .normal)
        linkButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        linkButton.addTarget(self, action: #selector(showLinkTap(_:)), for: .touchUpInside)
        view.addSubview(linkButton)
        linkButton.snp.makeConstraints { maker in
                maker.top.equalTo(view.safeAreaLayoutGuide).offset(10)
                maker.leading.equalToSuperview().offset(15)
                maker.trailing.equalToSuperview().offset(-15)
                maker.height.equalTo(FilterView.height)
            }
        
        view.addSubview(tabsView)
        tabsView.snp.makeConstraints { maker in
            maker.top.equalTo(linkButton.snp.bottom).offset(5)
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

        allMarketDappListViewController.parentNavigationController = parentNavigationController
        ethMarketDappListViewController.parentNavigationController = parentNavigationController
        bscMarketDappListViewController.parentNavigationController = parentNavigationController
        safeMarketDappListViewController.parentNavigationController = parentNavigationController

        subscribe(disposeBag, viewModel.currentTabDriver) { [weak self] in self?.sync(currentTab: $0) }
    }
    
    private func sync(currentTab: MarketDappModule.Tab) {
        tabsView.select(index: currentTab.rawValue)
        setViewPager(tab: currentTab)
    }

    private func onSelectTab(index: Int) {
        guard let tab = MarketDappModule.Tab(rawValue: index) else {
            return
        }
        viewModel.onSelect(tab: tab)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @objc
    private func showLinkTap(_ sender: UIButton) {
        let vc = MarketDappLinkViewController()
        parentNavigationController?.pushViewController(vc, animated: true)
    }
}

extension MarketDappViewController {

    private func setViewPager(tab: MarketDappModule.Tab) {
        pageViewController.setViewControllers([viewController(tab: tab)], direction: .forward, animated: false)
    }

    private func viewController(tab: MarketDappModule.Tab) -> UIViewController {
        switch tab {
        case .ALL: return allMarketDappListViewController
        case .ETH: return ethMarketDappListViewController
        case .BSC: return bscMarketDappListViewController
        case .SAFE: return safeMarketDappListViewController
        }
    }
}
