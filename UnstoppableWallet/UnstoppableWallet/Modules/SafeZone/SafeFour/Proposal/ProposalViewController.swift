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
        subscribe(disposeBag, viewModel.stateDriver) { [weak self] in self?.sync(state: $0) }
    }
    
    private func sync(state: ProposalViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinner.isHidden = (self?.viewItems.count)! > 0 ? true : false
                self?.emptyView.isHidden = true
                
            case let .completed(datas):
                self?.spinner.isHidden = true
                self?.emptyView.isHidden = datas.count > 0 ? true : false
                self?.viewItems = datas
                self?.tableView.reload()
                
            case .failed(_):
                guard let count = self?.viewItems.count, count > 0 else { return (self?.emptyView.isHidden = false)! }
                
            }
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

    func buildSections() -> [SectionProtocol] {
        let rows = viewItems.map{ row(viewItem: $0)}
        return [Section(id: "proposal", paginating: true, rows: rows)]
    }
    
    func onBottomReached() {
        viewModel.loadMore()
    }
}
