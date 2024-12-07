import UIKit
import ComponentKit
import SectionsTableView
import SnapKit
import ThemeKit
import RxSwift
import RxCocoa
import MarketKit
import HUD

class MasterNodeViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: MasterNodeViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var viewItems = [MasterNodeViewModel.ViewItem]()
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    private let tipsCell = Safe4WarningCell()
    private let warningCell = Safe4WarningCell()

    private let nodeSearchCell = Safe4NodeSearchCell()
    private let nodeSearchCautionCell = FormCautionCell()

    private var isLoaded = false
    private var isSearch = false
    
    weak var parentNavigationController: UINavigationController?

    init(viewModel: MasterNodeViewModel) {
        self.viewModel = viewModel
        super.init()
        hidesBottomBarWhenPushed = true
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
        tableView.registerCell(forClass: MasterNodeCell.self)
        
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
        
        tipsCell.bind(text: "safe_zone.safe4.node.register.tips".localized, type: .normal)
        
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
        
        nodeSearchCell.setInput(keyboardType: .default, placeholder: "safe_zone.safe4.search.input.master.tips".localized)
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
    
    private func sync(state: MasterNodeViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinner.isHidden = (self?.viewItems.count)! > 0 ? true : false
                self?.hiddenEmptyView(isHidden: true)
                
            case let .completed(datas):
                guard self?.isSearch == false else{ return }
                self?.spinner.isHidden = true
                self?.hiddenEmptyView(isHidden: datas.count > 0)
                self?.viewItems = datas
                self?.tableView.reload()
                
            case let .searchResults(datas):
                self?.spinner.isHidden = true
                self?.hiddenEmptyView(isHidden: datas.count > 0)
                self?.viewItems = datas
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

    @objc 
    private func onRefresh() {
        viewModel.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }
    
    @objc 
    private func add() {
        switch viewModel.nodeType {
        case .masterNode:
            HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.account.node.state.master".localized))
        case .superNode:
            HudHelper.instance.show(banner: .error(string: "safe_zone.safe4.account.node.state.super".localized))
        case .normal:
            guard let vc = MasterNodeRegisterModule.viewController() else { return }
            navigationController?.pushViewController(vc, animated: true)
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
extension MasterNodeViewController {
    private func row(viewItem: MasterNodeViewModel.ViewItem) -> RowProtocol {
        
        Row<MasterNodeCell>(
            id: "MasterNode_row",
            height: MasterNodeCell.height(),
            autoDeselect: true,
            bind: { cell, _ in
                cell.bind(viewItem: viewItem)
                cell.toDetail = { [weak self] in
                    guard let strongSelf = self, let vc = MasterNodeDetailModule.viewController(nodeType: strongSelf.viewModel.nodeType, viewItem: viewItem, viewType: .Detail) else { return }
                    vc.needReload = {
                        strongSelf.tableView.reload()
                    }
                    strongSelf.parentNavigationController?.pushViewController(vc, animated: true)
                }
                cell.toJoin = { [weak self] in
                    guard let strongSelf = self, let vc = MasterNodeDetailModule.viewController(nodeType: strongSelf.viewModel.nodeType, viewItem: viewItem, viewType: .JoinPartner) else { return }
                    vc.needReload = {
                        strongSelf.tableView.reload()
                    }
                    strongSelf.parentNavigationController?.pushViewController(vc, animated: true)
                }
                cell.toEdit = { [weak self] in
                    guard let strongSelf = self else { return }
                    guard let vc = MasterNodeChangeModule.viewController(viewItem: viewItem) else { return }
                    vc.needReload = {
                        strongSelf.viewModel.refresh()
                    }
                    strongSelf.parentNavigationController?.pushViewController(vc, animated: true)
                }
                cell.toAddLock = { [weak self] in
                    guard let strongSelf = self else { return }
                    guard let vc = AddLockDaysModule.viewController(type: .masterNode(info: viewItem.info)) else { return }
                    strongSelf.parentNavigationController?.pushViewController(vc, animated: true)
                }
            }
        )
    }
    
    var tipsRow: RowProtocol {
        StaticRow(
                cell: tipsCell,
                id: "node-tips",
                dynamicHeight: { [weak self] containerWidth in
                        self?.tipsCell.height(containerWidth: containerWidth) ?? 0
                }
        )
    }
    
    var waringRow: RowProtocol {
        StaticRow(
                cell: warningCell,
                id: "node-warning",
                dynamicHeight: { [weak self] containerWidth in
                        self?.warningCell.height(containerWidth: containerWidth) ?? 0
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
}
extension MasterNodeViewController: SectionsDataSource {
    
    func buildSections() -> [SectionProtocol] {
        var waringRows = [RowProtocol]()
        
        if viewModel.type == .All {
            waringRows.append(searchRow)
            waringRows.append(searchCautionRow)
        }
        
        waringRows.append(tipsRow)
        if viewModel.nodeType != .normal {
            warningCell.bind(text: viewModel.nodeType.warnings, type: .warning)
            waringRows.append(waringRow)
        }
        let rows = viewItems.map{ row(viewItem: $0)}
        return [Section(id: "warings", rows: waringRows),
            Section(id: "MasterNode", paginating: true, rows: rows)]
    }
    
    func onBottomReached() {
        viewModel.loadMore()
    }
}
