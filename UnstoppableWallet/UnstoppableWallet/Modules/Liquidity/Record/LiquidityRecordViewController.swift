import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit
import HUD

class LiquidityRecordViewController: ThemeViewController {
    
    private let disposeBag = DisposeBag()
    private let viewModel: LiquidityRecordViewModel
    private let v3ViewModel: LiquidityV3RecordViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinner = HUDActivityView.create(with: .medium24)
    private var viewItems = [LiquidityRecordViewModel.RecordItem]()
    private var v3ViewItems = [LiquidityV3RecordViewModel.V3RecordItem]()
    
    private let refreshControl = UIRefreshControl()
    private let emptyView = PlaceholderView()
    weak var parentNavigationController: UINavigationController?
    private var loadingStatus: (Bool, Bool) = (false, false)
    
    init(viewModel: LiquidityRecordViewModel, v3ViewModel: LiquidityV3RecordViewModel) {
        self.viewModel = viewModel
        self.v3ViewModel = v3ViewModel
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

        tableView.sectionDataSource = self

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        
        tableView.registerCell(forClass: LiquidityRecordCell.self)
        tableView.registerCell(forClass: LiquidityV3RecordCell.self)
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.buildSections()
        
        view.addSubview(emptyView)
        emptyView.snp.makeConstraints { maker in
            maker.edges.equalTo(view.safeAreaLayoutGuide)
        }

        emptyView.image = UIImage(named: "add_to_wallet_2_48")
        emptyView.text = "liquidity.empty.description".localized
        emptyView.isHidden = true
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.startAnimating()

        subscribe(disposeBag, viewModel.statusDriver) { [weak self] state in
            self?.sync(state: state)
        }
        
        subscribe(disposeBag, v3ViewModel.statusDriver) { [weak self] state in
            self?.sync(state: state)
        }
        
        viewModel.refresh()
        v3ViewModel.refresh()
        loadingStatus = (true, true)
    }
    
    private func sync(state: LiquidityRecordService.State) {

        DispatchQueue.main.async { [weak self] in
            if case .loading = state {
                self?.loadingStatus.0 = true
            }else {
                self?.loadingStatus.0 = false
            }
            
            switch state {
            case let .completed(datas):
                self?.sync(data: datas)
            default: ()
            }
            self?.updateSpinner()
        }
    }
    
    private func sync(state: LiquidityV3RecordService.State) {
        DispatchQueue.main.async { [weak self] in
            if case .loading = state {
                self?.loadingStatus.1 = true
            }else {
                self?.loadingStatus.1 = false
            }
            
            switch state {
            case let .completed(datas):
                self?.sync(datas: datas)
            default: ()
            }
            self?.updateSpinner()
        }
    }
    private func updateSpinner() {
        if loadingStatus.0 == true || loadingStatus.1 == true {
            spinner.isHidden = false
            emptyView.isHidden = true
        }else {
            spinner.isHidden = true
            emptyView.isHidden = v3ViewItems.count > 0 || viewItems.count > 0
        }
    }

    private func sync(data: [LiquidityRecordViewModel.RecordItem]) {
        self.viewItems = data
        tableView.reload()
    }
    
    private func sync(datas: [LiquidityV3RecordViewModel.V3RecordItem]) {
        self.v3ViewItems = datas
        tableView.reload()
    }
    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.refreshControl = refreshControl
    }

    @objc private func onRefresh() {
        viewModel.refresh()
        v3ViewModel.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    private func show(error: String?) {
        if let message  = error {
            HudHelper.instance.show(banner: .error(string: message))
        }
    }
    
    private func removeConfirmation(viewItem: LiquidityRecordViewModel.RecordItem) {
        let viewController = LiquidityRemoveConfirmViewController(viewModel: viewModel, recordItem: viewItem)
        parentNavigationController?.pushViewController(viewController, animated: true)
    }
    
    func toDetailView(viewItem: LiquidityV3RecordViewModel.V3RecordItem) {
        let viewController = LiquidityV3RecordDetailViewController(viewModel: v3ViewModel, viewItem: viewItem)
        parentNavigationController?.pushViewController(viewController, animated: true)
    }
}

extension LiquidityRecordViewController: SectionsDataSource {
    
    private func row(viewItem: LiquidityRecordViewModel.RecordItem) -> RowProtocol {
        
        Row<LiquidityRecordCell>(
                id: "v2_row",
                height: LiquidityRecordCell.height(),
                autoDeselect: true,
                bind: { cell, _ in
                    cell.bind(viewItem: viewItem)
                },
                action: { _ in
                    self.removeConfirmation(viewItem: viewItem)
                }
        )
    }
    
    private func row(viewItem: LiquidityV3RecordViewModel.V3RecordItem) -> RowProtocol {
        
        Row<LiquidityV3RecordCell>(
                id: "v3_row",
                height: LiquidityV3RecordCell.height(),
                autoDeselect: true,
                bind: { cell, _  in
                    cell.bind(viewItem: viewItem)
                },
                action: { _ in
                    self.toDetailView(viewItem: viewItem)
                }
        )
    }

    func buildSections() -> [SectionProtocol] {
        
        var sections = [SectionProtocol]()
        if viewItems.count > 0 {
            let v2rows = viewItems.map{ row(viewItem: $0)}
            let section = Section(id: "v2", headerState: .text(text: "V2 LP", topMargin: 25, bottomMargin: 15), rows: v2rows)
            sections.append(section)
        }
        
        if v3ViewItems.count > 0 {
            let v3Rows = v3ViewItems.map{ row(viewItem: $0)}
            let section = Section(id: "v3", headerState: .text(text: "V3 LP", topMargin: 25, bottomMargin: 15), rows: v3Rows)
            sections.append(section)
        }
        
        return sections
    }
}
