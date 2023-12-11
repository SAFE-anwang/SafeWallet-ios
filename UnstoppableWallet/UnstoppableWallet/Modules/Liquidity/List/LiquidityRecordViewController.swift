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
        
        subscribe(disposeBag, viewModel.viewItemsDriver) { [weak self] in self?.sync(data: $0) }
    }
    
    private func sync(data: [LiquidityRecordViewModel.RecordItem]) {
        self.spinner.isHidden = true
        self.viewItems = data
        tableView.reload()
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
                        self.viewModel.removeLiquidity(recordItem: item)
                    }
                }
        )

    }

    func buildSections() -> [SectionProtocol] {
        let rows = viewItems.map{ row(viewItem: $0)}
        return [Section(id: "",  rows: rows)]
    }

}
