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
        title = "safe_zone.row.masterNode".localized
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "safe4_add_2_24"), style: .plain, target: self, action: #selector(add))
        
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
        tableView.buildSections()
        
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
        
        tipsCell.bind(text: "注册成为主节点，则不能再注册成为超级节点", type: .normal)
        
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
    }
    
    private func sync(state: MasterNodeViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinner.isHidden = (self?.viewItems.count)! > 0 ? true : false
                self?.emptyView.isHidden = true
                
            case let .completed(datas):
                self?.spinner.isHidden = true
                self?.emptyView.isHidden =  datas.count > 0 ? true : false
                self?.viewItems = datas
                self?.tableView.reload()
                
            case .failed(_):
                self?.spinner.isHidden = true
                guard let count = self?.viewItems.count, count > 0 else { return (self?.emptyView.isHidden = false)! }
                
            }
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
            HudHelper.instance.show(banner: .error(string: "已经是主节点，不能再注册"))
        case .superNode:
            HudHelper.instance.show(banner: .error(string: "已经是超级节点，不能再注册"))
        case .normal:
            guard let vc = MasterNodeRegisterModule.viewController() else { return }
            navigationController?.pushViewController(vc, animated: true)
        }

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
            },
            action: { cell in
                guard cell.joinEnabled else { return }
                guard let vc = MasterNodeDetailModule.viewController(viewItem: viewItem) else { return }
                self.navigationController?.pushViewController(vc, animated: true)
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
}
extension MasterNodeViewController: SectionsDataSource {
    
    func buildSections() -> [SectionProtocol] {
        var waringRows = [RowProtocol]()
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
