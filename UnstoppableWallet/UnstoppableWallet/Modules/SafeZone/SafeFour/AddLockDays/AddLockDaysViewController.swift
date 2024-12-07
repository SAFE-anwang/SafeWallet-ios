import Foundation
import UIKit
import SectionsTableView
import SnapKit
import ThemeKit
import UIExtensions
import RxSwift
import RxCocoa
import ComponentKit
import EvmKit
import BigInt

class AddLockDaysViewController: ThemeViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: AddLockDaysViewModel
    private let tableView = SectionsTableView(style: .grouped)
    private let spinnerView = Safe4SpinnerView()
    private var isLoaded = false
    private var dataArray = [AddLockDaysViewModel.LockInfo]()
    
    init(viewModel: AddLockDaysViewModel) {
        self.viewModel = viewModel
        
        super.init()
        
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.node.locked.days.add.title".localized
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        tableView.registerCell(forClass: AddLockDaysRecordCell.self)

        spinnerView.isHidden = true
        view.addSubview(spinnerView)
        spinnerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        didLoad()
        
        subscribe(disposeBag, viewModel.stateObservable) {  [weak self] in
            self?.sync(state: $0)
        }
        
        viewModel.requestLockRecoardInfos()
    }
    
    private func sync(state: AddLockDaysViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .loading:
                self?.spinnerView.isHidden = false
                
            case let .dataArray(infos):
                self?.dataArray = infos
                self?.tableView.reload()
                
            case let .success(message):
                self?.spinnerView.isHidden = true
                HudHelper.instance.show(banner: .success(string: message ?? ""))
                self?.navigationController?.popViewController(animated: true)
                
            case let .failed(error):
                self?.spinnerView.isHidden = true
                HudHelper.instance.show(banner: .error(string: error ?? ""))
            }
        }
    }
    
    private func didLoad() {
        tableView.buildSections()
        isLoaded = true
    }
    
    private func reloadTable() {
        guard isLoaded else { return }
        UIView.animate(withDuration: 0) {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }
}
extension AddLockDaysViewController: SectionsDataSource {
    
    private func row(viewItem: AddLockDaysViewModel.LockInfo) -> RowProtocol {
        
        Row<AddLockDaysRecordCell>(
                id: "row",
                height: AddLockDaysRecordCell.height(),
                autoDeselect: true,
                bind: { [viewModel] cell, _ in
                    cell.bind(info: viewItem)
                    cell.toMinus = { [weak self] in
                        viewItem.minus()
                        self?.tableView.reload()
                    }
                    
                    cell.toPlus = { [weak self] in
                        viewItem.plus()
                        self?.tableView.reload()
                    }
                    
                    cell.toAdd = {[weak self] in
                        let viewController = BottomSheetModule.addLockDaysConfirmation(days:  viewItem.selectedLockedDays.description) {
                            viewModel.addLock(info: viewItem)
                        }
                        self?.present(viewController, animated: true)

                    }
                }
        )
    }

    func buildSections() -> [SectionProtocol] {
        let rows = dataArray.map{ row(viewItem: $0)}
        return [Section(id: "record", headerState: .text(text: "safe_zone.safe4.node.locked.days.tips".localized, topMargin: 0, bottomMargin: 15),footerState: .margin(height: .margin32), rows: rows)]
    }
}
