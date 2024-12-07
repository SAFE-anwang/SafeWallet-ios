import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import RxSwift
import RxCocoa
import MarketKit
import HUD

class ProposalViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: ProposalViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var viewItems = [ProposalViewModel.ViewItem]()
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    
    weak var parentNavigationController: UINavigationController?
    
    private let nodeSearchCell = Safe4NodeSearchCell()
    private let nodeSearchCautionCell = FormCautionCell()

    private var isLoaded = false
    private var isSearch = false

    init(viewModel: ProposalViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
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
        tableView.registerCell(forClass: ProposalCell.self)
        
        tableView.sectionDataSource = self

        emptyView.frame = CGRect(x: 0, y: 0, width: view.width, height: 250)
        emptyView.image = UIImage(named: "safe4_empty")
        emptyView.text = "safe_zone.safe4.empty.description".localized

        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.startAnimating()
        viewModel.refresh()
        
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
        
        nodeSearchCell.setInput(keyboardType: .numberPad, placeholder: "safe_zone.safe4.node.proposal.id".localized)
        nodeSearchCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        nodeSearchCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }

        nodeSearchCell.onSearch = { [weak self] text in
            self?.isSearch = (text?.count ?? 0) > 0
            self?.view.endEditing(true)
            self?.viewModel.search(text: text)
        }
        
        subscribe(disposeBag, viewModel.searchCautionDriver) {  [weak self] in
            self?.nodeSearchCautionCell.set(caution: $0)
            self?.reloadTable()
        }
    }
    
    private func sync(state: ProposalViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinner.isHidden = (self?.viewItems.count)! > 0 ? true : false
                self?.hiddenEmptyView(isHidden: true)

            case let .completed(datas):
                guard self?.isSearch == false else{ return }
                self?.spinner.isHidden = true
                self?.viewItems = datas
                self?.hiddenEmptyView(isHidden: datas.count > 0)
                self?.tableView.reload()
                
            case let .searchResults(datas):
                self?.spinner.isHidden = true
                self?.viewItems = datas
                self?.hiddenEmptyView(isHidden: datas.count > 0)
                self?.tableView.reload()
                
            case .failed(_):
                self?.spinner.isHidden = true
                guard let count = self?.viewItems.count, count > 0 else {
                    self?.hiddenEmptyView(isHidden: false)
                    return
                }
            }
            self?.didLoad()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.refreshControl = refreshControl
    }

    @objc private func onRefresh() {
        viewModel.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
    
    func didLoad() {
        tableView.buildSections()
        isLoaded = true
    }

    func reloadTable() {
        guard isLoaded else { return }
        UIView.animate(withDuration: 0) {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }
    
    private func hiddenEmptyView(isHidden: Bool) {
        tableView.tableFooterView = isHidden ? nil : emptyView
    }
}

extension ProposalViewController: SectionsDataSource {
    private func row(viewItem: ProposalViewModel.ViewItem) -> RowProtocol {
        
        Row<ProposalCell>(
                id: "proposal_row",
                height: ProposalCell.height(),
                autoDeselect: true,
                bind: { cell, _ in
                    cell.bind(viewItem: viewItem)
                },
                action: { _ in
                    guard let vc = ProposalDetailModule.viewController(viewItem: viewItem) else{ return }
                    self.parentNavigationController?.pushViewController(vc, animated: true)
                }
        )
    }
    
    var searchRow: RowProtocol {
        StaticRow(
                cell: nodeSearchCell,
                id: "node-search",
                separatorInset: UIEdgeInsets(top: CGFloat.margin2, left: 0, bottom: CGFloat.margin2, right: 0),
                dynamicHeight: { [weak self] containerWidth in
                        self?.nodeSearchCell.height(containerWidth: containerWidth) ?? 0
                }
        )
    }
    
    var searchCautionRow: RowProtocol {
        StaticRow(
                cell: nodeSearchCautionCell,
                id: "search-warning",
                dynamicHeight: { [weak self] containerWidth in
                    self?.nodeSearchCautionCell.height(containerWidth: containerWidth) ?? 0
                }
        )
    }

    func buildSections() -> [SectionProtocol] {
        var proposalRows = [RowProtocol]()

        if case .All = viewModel.type {
            proposalRows.append(searchRow)
            proposalRows.append(searchCautionRow)
        }
        let rows = viewItems.map{ row(viewItem: $0)}
        proposalRows.append(contentsOf: rows)
        return [Section(id: "proposal", paginating: true, rows: proposalRows)]
    }
    
    func onBottomReached() {
        guard isSearch == false else{ return }
        viewModel.loadMore()
    }
}
