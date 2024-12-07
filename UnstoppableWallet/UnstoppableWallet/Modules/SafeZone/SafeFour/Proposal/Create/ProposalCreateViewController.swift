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

class ProposalCreateViewController: KeyboardAwareViewController {
    private let disposeBag = DisposeBag()
    private let viewModel: ProposalCreateViewModel
    private let tableView = SectionsTableView(style: .plain)
    private var isLoaded = false
    
    private let titleCell: ProposalInputCell
    private let titleCautionCell = FormCautionCell()

    private let descriptionCell: ProposalInputCell
    private let descriptionCautionCell = FormCautionCell()
    
    private let balanceCautionCell = FormCautionCell()
    
    private let safeAmountCell: ProposalInputCell
    private let safeAmountCautionCell = FormCautionCell()
    
    private let payTimesCell: ProposalInputCell
    private let payTimesCautionCell = FormCautionCell()
    private let datePickerCell: ProposalDatePickerCell
    
    private let payTimeCautionCell = FormCautionCell()

    private let buttonCell = PrimaryButtonCell()
    
    init(viewModel: ProposalCreateViewModel) {
        self.viewModel = viewModel
        
        titleCell = ProposalInputCell(viewModel: viewModel, type: .title)
        descriptionCell = ProposalInputCell(viewModel: viewModel, type: .desc)
        safeAmountCell = ProposalInputCell(viewModel: viewModel, type: .safeAmount)
        payTimesCell = ProposalInputCell(viewModel: viewModel, type: .payTimes)
        datePickerCell = ProposalDatePickerCell(viewModel: viewModel)
        
        super.init(scrollViews: [tableView])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "safe_zone.safe4.create.proposal".localized
        
        view.addEndEditingTapGesture()
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }
    
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionDataSource = self
        
        buttonCell.set(style: .yellow)
        buttonCell.title = "send.next_button".localized
        buttonCell.onTap = { [weak self] in
            self?.toSendVc()
        }
        
        titleCell.onChangeHeight = { [weak self] in self?.reloadTable()}
        titleCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        descriptionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        descriptionCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        safeAmountCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        payTimeCautionCell.onChangeHeight = { [weak self] in self?.reloadTable() }
        
        subscribe(disposeBag, viewModel.balanceDriver) {  [weak self] _ in
            self?.tableView.reload()
        }
        
        subscribe(disposeBag, viewModel.balanceCautionDriver) {  [weak self] in
            self?.balanceCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.titleCautionDriver) {  [weak self] in
            self?.titleCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.descCautionDriver) {  [weak self] in
            self?.descriptionCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.amountCautionDriver) {  [weak self] in
            self?.safeAmountCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, viewModel.payTypeDriver) {  [weak self] _ in
            self?.tableView.reload()
        }
        
        subscribe(disposeBag, viewModel.startPayTimeCautionDriver) {  [weak self] in
            self?.payTimeCautionCell.set(caution: $0)
            self?.tableView.reload()
        }

        subscribe(disposeBag, viewModel.payTimesCautionDriver) {  [weak self] in
            self?.payTimesCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        subscribe(disposeBag, viewModel.payTimesDriver) {  [weak self] in
            self?.payTimesCell.setInput(value: $0?.description)
            self?.reloadTable()
        }
        didLoad()
    }
}
private extension ProposalCreateViewController {
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
    
    func toSendVc() {
        guard let sendData = viewModel.sendData else { return }
        let vc = ProposalSendViewController(viewModel: viewModel, sendData: sendData)
        navigationController?.pushViewController(vc, animated: true)
    }
}

private extension ProposalCreateViewController {
    
    func balanceCell(title: String, value: String, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        CellBuilderNew.buildStatic(cell: cell, rootElement: .hStack([
            .margin16,
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.required, for: .horizontal)
                component.text = title
            },
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = .themeLeah
                component.setContentHuggingPriority(.defaultLow, for: .horizontal)
                component.text = value
            }
        ]), layoutMargins: UIEdgeInsets(top: .margin16, left: .margin16, bottom: .margin8, right: .margin16))
        return cell
    }
    
    func payTypeCell(viewModel: ProposalCreateViewModel, backgroundStyle: BaseSelectableThemeCell.BackgroundStyle) -> BaseSelectableThemeCell {
        let cell = BaseSelectableThemeCell()
        cell.set(backgroundStyle: backgroundStyle)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear
        CellBuilderNew.buildStatic(cell: cell, rootElement: .vStack([
            .margin8,
            .text { (component: TextComponent) -> () in
                component.font = .subhead1
                component.textColor = .themeGray
                component.setContentHuggingPriority(.required, for: .vertical)
                component.text = "safe_zone.safe4.pay.method".localized
            },
            .hStack([
                .secondaryButton { (component: SecondaryButtonComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .horizontal)
                    component.button.semanticContentAttribute = .forceLeftToRight
                    component.button.titleLabel?.font = .subhead1
                    component.button.setTitleColor(.themeLeah, for: .normal)
                    component.button.setImage(UIImage(named: "circle_radiooff_24")?.withTintColor(.themeIssykBlue), for: .normal)
                    component.button.setImage(UIImage(named: "circle_radioon_24")?.withTintColor(.themeIssykBlue), for: .selected)
                    component.button.setTitle("一次", for: .normal)
                    component.button.isSelected = viewModel.payType == .all
                    component.onTap = {
                        viewModel.update(payType: .all)
                    }
                },
                .secondaryButton { (component: SecondaryButtonComponent) -> () in
                    component.setContentHuggingPriority(.required, for: .horizontal)
                    component.button.semanticContentAttribute = .forceLeftToRight
                    component.button.titleLabel?.font = .subhead1
                    component.button.setTitleColor(.themeLeah, for: .normal)
                    component.button.setImage(UIImage(named: "circle_radiooff_24")?.withTintColor(.themeIssykBlue), for: .normal)
                    component.button.setImage(UIImage(named: "circle_radioon_24")?.withTintColor(.themeIssykBlue), for: .selected)
                    component.button.setTitle("safe_zone.safe4.pay.method.instalment".localized, for: .normal)
                    component.button.isSelected = viewModel.payType == .periodization
                    component.onTap = {
                        viewModel.update(payType: .periodization)
                    }
                },
                .text { (component: TextComponent) -> () in}
            ])
        ]), layoutMargins: UIEdgeInsets(top: .margin16, left: .margin16, bottom: .margin8, right: .margin16))
        return cell
    }
}

private extension ProposalCreateViewController {
    var proposalInputRows: [RowProtocol] {
        [
            StaticRow(
                    cell: titleCell,
                    id: "title-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.titleCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: titleCautionCell,
                    id: "title-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.titleCautionCell.height(containerWidth: containerWidth) ?? 0
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
                cell: balanceCell(title: "safe_zone.safe4.proposal.pool.balance".localized, value: ": \(viewModel.balance ?? "--")", backgroundStyle: .transparent),
                id: "safe-balance",
                height: .heightSingleLineCell
            ),
            StaticRow(
                    cell: balanceCautionCell,
                    id: "balance-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.balanceCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),

            StaticRow(
                    cell: safeAmountCell,
                    id: "safeAmount-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.safeAmountCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: safeAmountCautionCell,
                    id: "safeAmount-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.safeAmountCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: payTypeCell(viewModel: viewModel, backgroundStyle: .transparent),
                    id: "payType-input",
                    height: .heightDoubleLineCell
            ),
            StaticRow(
                    cell: datePickerCell,
                    id: "datePicker-input",
                    height: .heightDoubleLineCell
            ),
            StaticRow(
                    cell: payTimeCautionCell,
                    id: "startPayTime-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.payTimeCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            )
        ]
    }
    
    var periodizationRows: [RowProtocol] {
        [
            StaticRow(
                    cell: payTimesCell,
                    id: "payTimes-input",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.payTimesCell.height(containerWidth: containerWidth) ?? 0
                    }
            ),
            StaticRow(
                    cell: payTimesCautionCell,
                    id: "payTimes-warning",
                    dynamicHeight: { [weak self] containerWidth in
                        self?.payTimesCautionCell.height(containerWidth: containerWidth) ?? 0
                    }
            )
        ]
    }
    
    var buttonSection: SectionProtocol {
        Section(
            id: "button",
            footerState: .margin(height: .margin32),
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

extension ProposalCreateViewController: SectionsDataSource {

    func buildSections() -> [SectionProtocol] {
        
        var proposalRows = [RowProtocol]()
        proposalRows.append(contentsOf: proposalInputRows)
        
        if case .periodization = viewModel.payType {
            proposalRows.append(contentsOf: periodizationRows)
        }
        
        return [Section(id: "proposal", rows: proposalRows),
                buttonSection,
        ]
    }
}
