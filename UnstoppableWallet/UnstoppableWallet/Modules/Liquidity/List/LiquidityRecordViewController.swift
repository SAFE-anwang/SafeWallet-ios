import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import ModuleKit
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class LiquidityRecordViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: LiquidityRecordViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var viewItems = [LiquidityRecordViewModel.RecordItem]()
    
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    
    init(viewModel: LiquidityRecordViewModel) {
        self.viewModel = viewModel
        super.init()

        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "liquidity.title.record".localized
        navigationItem.backBarButtonItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
        
        refreshControl.tintColor = .themeLeah
        refreshControl.alpha = 0.6
        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)

        tableView.sectionDataSource = self

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.registerCell(forClass: LiquidityRecordCell.self)
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.buildSections()
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }

        spinner.startAnimating()
        
        view.addSubview(emptyView)
        emptyView.snp.makeConstraints { maker in
            maker.edges.equalTo(view.safeAreaLayoutGuide)
        }

        emptyView.image = UIImage(named: "add_to_wallet_2_48")
        emptyView.text = "liquidity.empty.description".localized

//        view.addSubview(errorView)
//        errorView.snp.makeConstraints { maker in
//            maker.edges.equalTo(view.safeAreaLayoutGuide)
//        }
//
//        errorView.configureSyncError(action: { [weak self] in self?.onRetry() })

        subscribe(disposeBag, viewModel.loadingDriver) { [weak self] loading in
            self?.spinner.isHidden = !loading
        }
        subscribe(disposeBag, viewModel.viewItemsDriver) { [weak self] in self?.sync(data: $0) }
    }
    
    private func sync(data: [LiquidityRecordViewModel.RecordItem]) {
        self.spinner.isHidden = true
        self.emptyView.isHidden = data.count > 0
        self.viewItems = data
        tableView.reload()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.refreshControl = refreshControl
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
    
    private func removeConfirmation(viewItem: LiquidityRecordViewModel.RecordItem) {
        let viewController = BottomSheetModule.removeLiquidityConfirmation { [weak self] in
            self?.viewModel.removeLiquidity(recordItem: viewItem)
            self?.dismiss(animated: true)
        }
        present(viewController, animated: true)
    }
}

extension LiquidityRecordViewController: SectionsDataSource {

    
    private func row(viewItem: LiquidityRecordViewModel.RecordItem) -> RowProtocol {
        
        Row<LiquidityRecordCell>(
                id: "row",
                height: LiquidityRecordCell.height(),
                autoDeselect: true,
                bind: { cell, _ in
                    cell.bind(viewItem: viewItem) { item in
                        self.removeConfirmation(viewItem: item)
                    }
                }
        )

    }

    func buildSections() -> [SectionProtocol] {
        let rows = viewItems.map{ row(viewItem: $0)}
        return [Section(id: "",  rows: rows)]
    }

}
