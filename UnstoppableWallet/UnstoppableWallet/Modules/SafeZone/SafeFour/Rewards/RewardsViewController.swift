import UIKit
import ComponentKit
import SectionsTableView
import SnapKit
import ThemeKit
import RxSwift
import RxCocoa
import MarketKit
import HUD

class RewardsViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: RewardsViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private var viewItems = [RewardsViewModel.ViewItem]()
    private let refreshControl = UIRefreshControl()
    
    private let spinner = HUDActivityView.create(with: .medium24)
    private let emptyView = PlaceholderView()
    
    init(viewModel: RewardsViewModel) {
        self.viewModel = viewModel
        super.init()
        
        hidesBottomBarWhenPushed = true

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.rewards.title".localized
        navigationItem.largeTitleDisplayMode = .never
        
        refreshControl.tintColor = .themeLeah
        refreshControl.alpha = 0.6
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.registerCell(forClass: SuperNodeCell.self)
        
        tableView.sectionDataSource = self
        
        view.addSubview(emptyView)
        emptyView.snp.makeConstraints { maker in
            maker.edges.equalTo(view.safeAreaLayoutGuide)
        }
        emptyView.image = UIImage(named: "safe4_empty")
        emptyView.text = "safe_zone.safe4.empty.description".localized
        emptyView.isHidden = true
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.startAnimating()
        
        viewModel.refresh()
        tableView.buildSections()
        
        subscribe(disposeBag, viewModel.viewItemsDriver) { [weak self] in self?.sync(datas: $0) }
    }
    
    private func sync(datas: [RewardsViewModel.ViewItem]?) {
        guard let datas else {
            spinner.isHidden = false
            return
        }
        
        spinner.isHidden = true
        emptyView.isHidden = datas.count > 0
        viewItems = datas
        tableView.reload()
        
    }
    
    @objc private func onRefresh() {
        viewModel.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
}
private extension RewardsViewController {
    
    func buildRecordCell(date: String, amount: String, isFirst: Bool = false, isLast: Bool = false) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.selectionStyle = .none
        cell.set(backgroundStyle: .lawrence, cornerRadius: .cornerRadius12, isFirst: isFirst, isLast: isLast)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.setContentCompressionResistancePriority(.required, for: .horizontal)
                component.text = date
            },
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textAlignment = .right
                component.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                component.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
                component.text = amount
            }
        ]))
        return cell
    }
    
    private func row(date: String, amount: String) -> RowProtocol {
        StaticRow(
                cell: buildRecordCell(date: date, amount: amount),
                id: "row",
                height: .heightCell48
        )
    }
    
    private func headerRow() -> RowProtocol {
        StaticRow(
                cell: buildRecordCell(date: "日期", amount: "金额", isFirst: true),
                id: "header",
                height: .heightCell48
        )
    }
}

extension RewardsViewController: SectionsDataSource {

    func buildSections() -> [SectionProtocol] {
        var rows = [RowProtocol]()
        if viewItems.count > 0 {
            rows.append(headerRow())
            rows.append(contentsOf: viewItems.map{row(date: $0.date, amount: $0.amountStr)})
        }
        return [Section(id: "rewards", rows: rows)]
    }
    
    func onBottomReached() {

    }
}
