import UIKit
import RxSwift
import ThemeKit
import SectionsTableView
import ComponentKit
import HUD

class MarketDappListViewController: ThemeViewController {
    private let viewModel: MarketDappViewModel
    private let urlManager: UrlManager
    private let disposeBag = DisposeBag()

    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private let errorView = PlaceholderViewModule.reachabilityView()
    private let refreshControl = UIRefreshControl()
    private var viewItems: [MarketDappViewModel.ViewItem]?
    private let tab: MarketDappModule.Tab
    weak var parentNavigationController: UINavigationController?
    var headerView: UITableViewHeaderFooterView? { nil }

    init(viewModel: MarketDappViewModel, urlManager: UrlManager, tab: MarketDappModule.Tab) {
        self.viewModel = viewModel
        self.urlManager = urlManager
        self.tab = tab
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        refreshControl.tintColor = .themeLeah
        refreshControl.alpha = 0.6
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear

        tableView.sectionDataSource = self
        tableView.registerCell(forClass: PostCell.self)

        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }

        spinner.startAnimating()

        view.addSubview(errorView)
        errorView.snp.makeConstraints { maker in
            maker.edges.equalTo(view.safeAreaLayoutGuide)
        }
        
        errorView.configureSyncError(action: { [weak self] in self?.onRetry() })

        subscribe(disposeBag, viewModel.viewItemsDriver) { [weak self] in self?.sync(data: $0) }
        subscribe(disposeBag, viewModel.loadingDriver) { [weak self] loading in
            self?.spinner.isHidden = !loading
        }
        subscribe(disposeBag, viewModel.syncErrorDriver) { [weak self] visible in
            self?.errorView.isHidden = !visible
        }

        viewModel.onLoad(tab: self.tab)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        tableView.refreshControl = refreshControl
    }

    @objc private func onRetry() {
        refresh()
    }

    @objc private func onRefresh() {
        refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    private func refresh() {
        viewModel.refresh(tab: self.tab)
    }

    private func sync(data:([MarketDappViewModel.ViewItem], MarketDappModule.Tab)?) {
        guard self.tab ==  data?.1 else { return }
        self.viewItems = data?.0

        if viewItems != nil {
            tableView.bounces = true
        } else {
            tableView.bounces = false
        }
        tableView.reload()
    }

    private func open(url: String) {


        urlManager.open(url: url, from: parentNavigationController)//openWkwebView(url: url, from: parentNavigationController)
    }
    
}

extension MarketDappListViewController {
    
    private func rows(tableView: SectionsTableView, listViewItems: [MarktDapp]) -> [RowProtocol] {
        listViewItems.enumerated().map { index, listViewItem in
            marketDappListCell(
                    tableView: tableView,
                    backgroundStyle: .transparent,
                    listViewItem: listViewItem,
                    isFirst: index == 0,
                    isLast: false,
                    rowActionProvider: nil,
                    action:  { [weak self] in
                        self?.open(url: listViewItem.dlink)
                    })
        }
    }
    
    private func marketDappListCell(tableView: UITableView, backgroundStyle: BaseThemeCell.BackgroundStyle, listViewItem: MarktDapp, isFirst: Bool, isLast: Bool, rowActionProvider: (() -> [RowAction])?, action: (() -> ())?) -> RowProtocol {
        CellBuilderNew.row(
                rootElement: .hStack([
                    .image32 { component in
                        component.imageView.contentMode = .scaleAspectFill
                        component.imageView.clipsToBounds = true
                        component.imageView.cornerRadius = 16
                        component.imageView.layer.cornerCurve = .continuous
                        component.imageView.kf.setImage(
                                with: URL(string: listViewItem.icon),
                                placeholder: nil,
                                options: [.onlyLoadFirstFrame]
                        )
                    },
                    .vStackCentered([
                        .hStack([
                            .text { component in
                                component.font = .body
                                component.textColor = .themeLeah
                                component.text = listViewItem.name
                            }
                        ]),
                        .margin(1),
                        .hStack([
                            .text { component in
                                component.font = .subhead2
                                component.textColor = .themeGray
                                let  isZh = LanguageManager.shared.currentLanguage == "zh"
                                component.text = isZh ? listViewItem.desc : listViewItem.descEN
                                component.numberOfLines = 2
                            },

                        ])
                    ])
                ]),
                layoutMargins: UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10),
                tableView: tableView,
                id: "cell",
                height: 70,
                autoDeselect: true,
                rowActionProvider: rowActionProvider,
                bind: { cell in
                    cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
                },
                action: action
        )
    }
}


extension MarketDappListViewController: SectionsDataSource {

    func buildSections() -> [SectionProtocol] {
        let headerState: ViewState<UITableViewHeaderFooterView>

        if let headerView = headerView, let viewItems = viewItems, !viewItems.isEmpty {
            headerState = .static(view: headerView, height: .heightCell56)
        } else {
            headerState = .margin(height: 0)
        }
        
        var sections: [SectionProtocol] = [SectionProtocol]()
        if let viewItems = viewItems, !viewItems.isEmpty {
            for section in viewItems {
                sections.append(
                    Section(
                        id: "coins",
                        headerState: headerState,
                        footerState: .marginColor(height: .margin32, color: .clear) ,
                        rows: rows(tableView: tableView, listViewItems: section.subs)
                    ))
            }
        }
        return sections
        
    }

}



