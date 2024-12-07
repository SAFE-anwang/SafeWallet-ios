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

class SuperNodeRegisterViewController: KeyboardAwareViewController {
    private let disposeBag = DisposeBag()
    private let enodeTips = "safe_zone.safe4.node.enode.tips".localized
    private let viewModel: SuperNodeRegisterViewModel
    private let tableView = SectionsTableView(style: .plain)
    private var isLoaded = false
    private let balanceCautionCell = FormCautionCell()
    
    private let addressCell: SuperNodeRegisterCell
    private let addressCautionCell = FormCautionCell()
    
    private let nameCell: SuperNodeRegisterCell
    private let nameCautionCell = FormCautionCell()
    
    private let enodeCell: SuperNodeRegisterCell
    private let enodeCautionCell = FormCautionCell()
    private let enodeTipsCell = DescriptionCell()

    private let descriptionCell: SuperNodeRegisterCell
    private let descriptionCautionCell = FormCautionCell()
    
    private let sliderCell: SuperNodeRegisterSliderCell
    
    private let buttonCell = PrimaryButtonCell()
    
    init(viewModel: SuperNodeRegisterViewModel) {
        self.viewModel = viewModel
        
        addressCell = SuperNodeRegisterCell(viewModel: viewModel, type: .address)
        nameCell = SuperNodeRegisterCell(viewModel: viewModel, type: .name)
        enodeCell = SuperNodeRegisterCell(viewModel: viewModel, type: .ENODE)
        descriptionCell = SuperNodeRegisterCell(viewModel: viewModel, type: .desc)

        sliderCell = SuperNodeRegisterSliderCell(viewModel: viewModel)
        
        super.init(scrollViews: [tableView])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.SuperNodeRegister".localized
        
        view.addEndEditingTapGesture()
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
        
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        tableView.buildSections()
        
        buttonCell.set(style: .yellow)
        buttonCell.title = "send.next_button".localized
        buttonCell.setDebounceInterval(3)
        buttonCell.onTap = { [weak self] in
            self?.toSendVc()
        }
        
        addressCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        addressCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        nameCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        nameCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        enodeCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        enodeCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        enodeTipsCell.label.font = .subhead2
        enodeTipsCell.label.textColor = .themeGray
        enodeTipsCell.label.text = enodeTips
        
        descriptionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        descriptionCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        subscribe(disposeBag, viewModel.createModeDriver) {  [weak self] _ in
            self?.sliderCell.sync()
            self?.tableView.reload()
        }
        
        subscribe(disposeBag, viewModel.balanceDriver) {  [weak self] _ in
            self?.tableView.reload()
        }
        
        subscribe(disposeBag, viewModel.balanceCautionDriver) {  [weak self] in
            self?.balanceCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.addressDriver) {  [weak self] in
            self?.addressCell.setInput(value: $0)
            self?.tableView.reload()
        }
        
        subscribe(disposeBag, viewModel.addressCautionDriver) {  [weak self] in
            self?.addressCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.nameCautionDriver) {  [weak self] in
            self?.nameCautionCell.set(caution: $0)
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
                
        didLoad()
    }

    func toSendVc() {
        Task { [viewModel] in
            do {
               let isValid = try await viewModel.isValidInputParams()
                guard isValid else { return }
                guard let sendData = viewModel.sendData else { return }
                if navigationController?.viewControllers.last is SuperNodeSendViewController {
                    return
                }
                let vc = SuperNodeSendViewController(viewModel: viewModel, sendData: sendData)
                navigationController?.pushViewController(vc, animated: true)
            }catch{}
        }
    }
}

private extension SuperNodeRegisterViewController {
    
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
}
private extension SuperNodeRegisterViewController {
    
    func createModeCell(viewModel: SuperNodeRegisterViewModel) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: .transparent)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        CellBuilderNew.buildStatic(cell: cell, rootElement: .vStack([
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = .themeGray
                component.setContentHuggingPriority(.required, for: .vertical)
                component.text = "safe_zone.safe4.node.create.mode".localized
            },
            .hStack([
                .secondaryButton { (component: SecondaryButtonComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .horizontal)
                    component.button.semanticContentAttribute = .forceLeftToRight
                    component.button.titleLabel?.font = .subhead1
                    component.button.setTitleColor(.themeLeah, for: .normal)
                    component.button.setImage(UIImage(named: "circle_radiooff_24")?.withTintColor(.themeIssykBlue), for: .normal)
                    component.button.setImage(UIImage(named: "circle_radioon_24")?.withTintColor(.themeIssykBlue), for: .selected)
                    component.button.setTitle("safe_zone.safe4.node.create.mode.independence".localized, for: .normal)
                    component.button.isSelected = viewModel.createMode == .Independent
                    component.onTap = {
                        viewModel.update(mode: .Independent)
                    }
                },
                .secondaryButton { (component: SecondaryButtonComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .horizontal)
                    component.button.semanticContentAttribute = .forceLeftToRight
                    component.button.titleLabel?.font = .subhead1
                    component.button.setTitleColor(.themeLeah, for: .normal)
                    component.button.setImage(UIImage(named: "circle_radiooff_24")?.withTintColor(.themeIssykBlue), for: .normal)
                    component.button.setImage(UIImage(named: "circle_radioon_24")?.withTintColor(.themeIssykBlue), for: .selected)
                    component.button.setTitle("safe_zone.safe4.node.create.mode.crowdfunding".localized, for: .normal)
                    component.button.isSelected = viewModel.createMode == .crowdFunding
                    component.onTap = {
                        viewModel.update(mode: .crowdFunding)
                    }
                },
                .text { (component: TextComponent) -> () in}
            ])
        ]), layoutMargins: UIEdgeInsets(top: .margin12, left: .margin16, bottom: .margin8, right: .margin16))
        return cell
    }
    
    func balanceCell(lockNum: String, balance: String) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: .transparent)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        CellBuilderNew.buildStatic(cell: cell, rootElement: .vStack([
            .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeGray
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "safe_zone.safe4.account.lock".localized
                },
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeGray
                    component.textAlignment = .right
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "safe_zone.safe4.account.balance".localized
                },
            ]),
            .margin8,
            .hStack([
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeBlackAndWhite
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = "\(lockNum) SAFE"
                },
                .text { (component: TextComponent) -> () in
                    component.font = .subhead1
                    component.textColor = .themeBlackAndWhite
                    component.textAlignment = .right
                    component.setContentHuggingPriority(.required, for: .vertical)
                    component.text = balance
                },
            ])
        ]), layoutMargins: UIEdgeInsets(top: .margin6, left: .margin16, bottom: .margin6, right: .margin16))
        return cell
    }
}
 
private extension SuperNodeRegisterViewController {
    
    var  nodeInfoInputRows: [RowProtocol] {
        [
            StaticRow(
                cell: createModeCell(viewModel: viewModel),
                id: "safe-createMode",
                height: .heightDoubleLineCell
            ),
            StaticRow(
                cell: balanceCell(lockNum: viewModel.createMode.lockAmount.description, balance: viewModel.balance),
                id: "safe-balance",
                height: .heightCell48
            ),
            StaticRow(
                    cell: balanceCautionCell,
                    id: "balance-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.balanceCautionCell.height(containerWidth: containerWidth) ?? 0
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
                    cell: nameCell,
                    id: "name-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.nameCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: nameCautionCell,
                    id: "name-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.nameCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
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
                    cell: enodeTipsCell,
                    id: "enode-tips",
                    dynamicHeight: { [weak self] containerWidth in
                        DescriptionCell.height(containerWidth: containerWidth, text: self?.enodeTips ?? "", font: self?.enodeTipsCell.label.font ?? .subhead2)
                    }
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
                    cell: sliderCell,
                    id: "slider-input",
                    height: .heightBottomWrapperBar
            )
        ]
    }
        
    var buttonSection: SectionProtocol {
        Section(
            id: "button",
            rows: [
                StaticRow(
                    cell: buttonCell,
                    id: "button",
                    height: PrimaryButtonCell.height
                ),
            ]
        )
    }

}

extension SuperNodeRegisterViewController: SectionsDataSource {
    func buildSections() -> [SectionProtocol] {
                
        return [Section(id: "nodeInfo", rows: nodeInfoInputRows),
                buttonSection,
        ]
    }
}

