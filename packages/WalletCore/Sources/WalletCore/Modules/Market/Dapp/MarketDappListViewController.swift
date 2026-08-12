import UIKit
import BigInt
import RxSwift
import SectionsTableView
import SwiftUI

class MarketDappListViewController: ThemeViewController {
    private let viewModel: MarketDappListViewModel
    private let disposeBag = DisposeBag()

    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private let errorView = PlaceholderViewModule.reachabilityView()
    private let refreshControl = UIRefreshControl()
    private var viewItems: [MarketDappListViewModel.ViewItem]?
    private var allViewItems: [MarketDappListViewModel.ViewItem]?
    private var searchText = ""
    private let _tab: MarketDappModule.Tab
    weak var parentNavigationController: UINavigationController?
    var headerView: UITableViewHeaderFooterView? { nil }

    init(viewModel: MarketDappListViewModel, tab: MarketDappModule.Tab) {
        self.viewModel = viewModel
        self._tab = tab
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

        viewModel.refresh()
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
        viewModel.refresh()
    }

    private func sync(data:([MarketDappListViewModel.ViewItem], MarketDappModule.Tab)?) {
        guard self._tab == data?.1 else { return }
        allViewItems = data?.0
        applyFilter()

        if viewItems != nil {
            tableView.bounces = true
        } else {
            tableView.bounces = false
        }
        tableView.reload()
    }

    private func open(url: String) {
        MarketDappModule.open(rawUrl: url, tab: _tab)
    }

    func apply(searchText: String) {
        self.searchText = searchText
        applyFilter()
    }

    private func applyFilter() {
        guard _tab == .SAFE else {
            viewItems = allViewItems
            tableView.reload()
            return
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            viewItems = allViewItems
            tableView.reload()
            return
        }
        viewItems = allViewItems?.compactMap { section in
            let subs = section.subs.filter { $0.matchesSafeDapp(query: query) }
            guard !subs.isEmpty else { return nil }
            return MarketDappListViewModel.ViewItem(subType: section.subType, subs: subs)
        }
        tableView.reload()
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
                    action: { [weak self] in
                        self?.open(item: listViewItem)
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
                        if let data = listViewItem.safeDappLogoData, let image = UIImage(data: data) {
                            component.imageView.kf.cancelDownloadTask()
                            component.imageView.image = image
                        } else {
                            component.imageView.kf.setImage(
                                with: URL(string: listViewItem.icon),
                                placeholder: UIImage(named: "safe-anwang_trx_32"),
                                options: [.onlyLoadFirstFrame]
                            )
                        }
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
                                component.text = listViewItem.safeSubtitle(isZh: isZh)
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

    private func open(item: MarktDapp) {
        guard _tab == .SAFE, let id = item.safeDappId else {
            open(url: item.dlink)
            return
        }

        Task { [weak self] in
            do {
                if try await SafeDappService.isFrozen(id: id) {
                    await MainActor.run {
                        self?.showAlert(title: "safe_dapp.frozen".localized, message: "safe_dapp.frozen_message".localized)
                    }
                    return
                }
                await MainActor.run {
                    if let fraudNum = item.safeDappFraudNum, fraudNum > 0 {
                        self?.showConfirm(
                            title: "safe_dapp.fraud_warning".localized,
                            message: "safe_dapp.fraud_warning_message".localized(fraudNum.description),
                            url: item.dlink
                        )
                    } else {
                        self?.open(url: item.dlink)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.showAlert(title: "alert.error".localized, message: error.localizedDescription)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "button.ok".localized, style: .default))
        present(controller, animated: true)
    }

    private func showConfirm(title: String, message: String, url: String) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "button.cancel".localized, style: .cancel))
        controller.addAction(UIAlertAction(title: "button.continue".localized, style: .default) { [weak self] _ in
            self?.open(url: url)
        })
        present(controller, animated: true)
    }
}

private extension MarktDapp {
    func matchesSafeDapp(query: String) -> Bool {
        [
            safeDappId?.description,
            name,
            safeDappKeyword,
            dlink,
            safeDappContractAddr,
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(query) }
    }

    func safeSubtitle(isZh: Bool) -> String {
        guard let safeDappId else {
            return isZh ? desc : descEN
        }
        let fraud = safeDappFraudNum?.description ?? "0"
        return "ID: \(safeDappId.description) · \("safe_dapp.fraud_count".localized): \(fraud)\n\(isZh ? desc : descEN)"
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
