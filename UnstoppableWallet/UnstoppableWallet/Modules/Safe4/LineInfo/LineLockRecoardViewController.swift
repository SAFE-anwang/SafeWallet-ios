import UIKit
import ThemeKit
import ComponentKit
import SectionsTableView
import RxSwift
import RxCocoa
import BitcoinCore

class LineLockRecoardViewController: ThemeViewController {

    private let disposeBag = DisposeBag()
    private let viewModel: LineLockRecoardViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private var viewItems = [LineLockRecoardViewModel.ViewItem]()
    
    init(lineLockRecoardViewModel: LineLockRecoardViewModel) {
        self.viewModel = lineLockRecoardViewModel
        super.init()
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "safe_lock.recoard.nav".localized
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear

        tableView.sectionDataSource = self
        tableView.buildSections()

        subscribe(disposeBag, viewModel.viewItemsDriver) { [weak self] in self?.sync(viewItems: $0) }
    }
    
    private func sync(viewItems: [LineLockRecoardViewModel.ViewItem]) {
        self.viewItems = viewItems
        tableView.buildSections()
        tableView.reloadData()
    }
    
    private func buildRecoardCell(amount: String, month: String, address: String,isLocked: Bool = false) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: .transparent)
        CellBuilderNew.buildStatic(cell: cell, rootElement: .vStack([
            .text { (component: TextComponent) -> () in
                component.font = .micro
                component.text = " "
            },
            .hStack([
                .image24 { (component: ImageComponent) -> () in
                    component.imageView.image = isLocked ? UIImage(named: "lock_24") : UIImage(named: "unlock_24")
                },
                .text { (component: TextComponent) -> () in
                    component.font = .body
                    component.textColor = .themeLeah
                    component.text = "\(amount) SAFE"
                },
                .text { (component: TextComponent) -> () in
                    component.font = .body
                    component.textColor = .themeYellowL
                    component.text = "safe_lock.amount.locked".localized(month)
                },
            ]),
            .text { (component: TextComponent) -> () in
                component.font = .body
                component.textColor = .themeLeah
                component.text = address
            },
            .margin4,
            
        ]))
        return cell
    }
}

extension LineLockRecoardViewController: SectionsDataSource {

    private func row(viewItem: LineLockRecoardViewModel.ViewItem) -> RowProtocol {
        StaticRow(
            cell: buildRecoardCell(amount: viewItem.lockAmount, month: "\(viewItem.lockMonth)", address: viewItem.address, isLocked: viewItem.isLocked),
                id: "row",
                height: 72,
                action: { [weak self] in
                    UIPasteboard.general.string = viewItem.address
                    HudHelper.instance.show(banner: .copied)
                    self?.tableView.deselectCell(withCoordinator: self?.transitionCoordinator, animated: true)
                }
        )
        
    }

    func buildSections() -> [SectionProtocol] {
        let rows = viewItems.map{ row(viewItem: $0)}
        return [Section(id: "", headerState: .text(text: viewModel.lockedBalanceTitle ?? "", topMargin: 25, bottomMargin: 15), rows: rows)]
    }

}
