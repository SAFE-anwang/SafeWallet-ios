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

class MasterNodeChangeViewController: KeyboardAwareViewController {
    private let disposeBag = DisposeBag()
    private var isLoaded = false
    private let tableView = SectionsTableView(style: .plain)
    private let spinner = HUDActivityView.create(with: .medium24)
    private let tipsCell = Safe4WarningCell()

    private let addressCell: MasterNodeChangeCell
    private let addressCautionCell = FormCautionCell()
    private let addressUpdateCell = Safe4NodeUpdateButtonCell()
    
    private let enodeCell: MasterNodeChangeCell
    private let enodeCautionCell = FormCautionCell()
    private let enodeUpdateCell = Safe4NodeUpdateButtonCell()

    private let descriptionCell: MasterNodeChangeCell
    private let descriptionCautionCell = FormCautionCell()
    private let descUpdateCell = Safe4NodeUpdateButtonCell()

    private let viewModel: MasterNodeChangeViewModel
    
    var needReload: (() -> Void)?
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(viewModel: MasterNodeChangeViewModel) {
        self.viewModel = viewModel
        
        addressCell = MasterNodeChangeCell(viewModel: viewModel, type: .address)
        enodeCell = MasterNodeChangeCell(viewModel: viewModel, type: .ENODE)
        descriptionCell = MasterNodeChangeCell(viewModel: viewModel, type: .desc)
        
        tipsCell.bind(text: "safe_zone.safe4.node.info.update.tips".localized, type: .normal)

        super.init(scrollViews: [tableView])
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        needReload?()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.node.edit".localized
        
        view.addEndEditingTapGesture()
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        tableView.buildSections()
        
        view.addSubview(spinner)
        spinner.snp.makeConstraints { maker in
            maker.center.equalToSuperview()
        }
        spinner.isHidden = true
        spinner.startAnimating()
        
        addressCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        addressCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        enodeCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        enodeCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        descriptionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        descriptionCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        addressUpdateCell.onTap = { [weak self] in
            self?.viewModel.commitChange(type: .address)
        }
        
        enodeUpdateCell.onTap = { [weak self] in
            self?.viewModel.commitChange(type: .ENODE)
        }
        
        descUpdateCell.onTap = { [weak self] in
            self?.viewModel.commitChange(type: .desc)
        }
        
        subscribe(disposeBag, viewModel.addressCautionDriver) {  [weak self] in
            self?.addressCautionCell.set(caution: $0)
            self?.reloadTable()
        }
                
        subscribe(disposeBag, viewModel.enodeCautionDriver) {  [weak self] in
            self?.enodeCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.descCautionDriver) {  [weak self] in
            self?.descriptionCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.stateDriver) {  [weak self] in
            self?.sync(state: $0)
        }
                
        didLoad()
    }
}
private extension MasterNodeChangeViewController {
    
    func didLoad() {
        tableView.buildSections()
        isLoaded = true
    }

    func reloadTable() {
        guard isLoaded else { return }
        DispatchQueue.main.async { [weak self] in
            UIView.animate(withDuration: 0) {
                self?.tableView.beginUpdates()
                self?.tableView.endUpdates()
            }
        }
    }
    
    func sync(state: MasterNodeChangeViewModel.State) {
        DispatchQueue.main.async { [weak self] in
            switch state {
                
            case let .unchanged(type):
                self?.syncUpdateCell(type: type)

            case let .didchanged(type):
                self?.syncUpdateCell(type: type)
                
            case .loading:
                self?.spinner.isHidden = false
                
            case .success:
                self?.spinner.isHidden = true
                self?.showSuccess()
                
            case let .faild(error):
                self?.spinner.isHidden = true
                guard error.count > 0 else { return }
                self?.show(error: error)
            }
        }
    }
    
    func showSuccess() {
        show(message: "safe_zone.safe4.update.success".localized)
    }
    
    func show(error: String) {
        HudHelper.instance.show(banner: .error(string: error))
    }
    
    func show(message: String) {
        HudHelper.instance.show(banner: .success(string: message))
    }
    
    func syncUpdateCell(type: MasterNodeInputType) {
        switch type {
        case .address:
             let isEnabled = viewModel.isChanged(type: type)
            addressUpdateCell.bind(isEnabled: isEnabled)
        case .ENODE:
            let isEnabled = viewModel.isChanged(type: type)
           enodeUpdateCell.bind(isEnabled: isEnabled)
        case .desc:
            let isEnabled = viewModel.isChanged(type: type)
           descUpdateCell.bind(isEnabled: isEnabled)
        }
    }
}

private extension MasterNodeChangeViewController {
    
    var nodeInfoInputRows: [RowProtocol] {
        [
            StaticRow(
                    cell: tipsCell,
                    id: "node-tips",
                    dynamicHeight: { [weak self] containerWidth in
                            self?.tipsCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: addressCell,
                    id: "address-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.addressCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: addressCautionCell,
                    id: "address-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.addressCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                cell: addressUpdateCell,
                    id: "address-Button",
                    height: .heightCell48
            ),
            StaticRow(
                    cell: enodeCell,
                    id: "enode-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.enodeCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: enodeCautionCell,
                    id: "enode-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.enodeCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                cell: enodeUpdateCell,
                    id: "enode-Button",
                    height: .heightCell48
            ),
            StaticRow(
                    cell: descriptionCell,
                    id: "desc-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.descriptionCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: descriptionCautionCell,
                    id: "desc-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.descriptionCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                cell: descUpdateCell,
                    id: "desc-Button",
                    height: .heightCell48
            ),
        ]
    }
}

extension MasterNodeChangeViewController: SectionsDataSource {
    func buildSections() -> [SectionProtocol] {
        return [Section(id: "nodeInfo", rows: nodeInfoInputRows)]
    }
}

