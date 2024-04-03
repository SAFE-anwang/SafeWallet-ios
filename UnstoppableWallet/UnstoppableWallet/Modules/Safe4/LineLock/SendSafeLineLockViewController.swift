import UIKit
import ThemeKit
import ComponentKit
import SectionsTableView
import RxSwift
import RxCocoa
import BitcoinCore

class SendSafeLineLockViewController: BaseSendViewController {
    private let disposeBag = DisposeBag()

    private let feeWarningViewModel: ITitledCautionViewModel

    private let feeCell: FeeCell
    private let feeCautionCell = TitledHighlightedDescriptionCell()
    
    private var safeLockTimeCell: SafeDropDownListCell?
    private var timeLockViewModel: TimeLockViewModel?
    
    
    private let lineLockTitleCell = TextCell()

    private let lockedValueCell: LineLockInputCell
    private let lockedValueCautionCell = FormCautionCell()

    private let startMonthCell: LineLockInputCell
    private let startMonthCautionCell = FormCautionCell()

    private let intervalMonthCell: LineLockInputCell
    private let intervalMonthCautionCell = FormCautionCell()

    private let lineLockCautionCell = TextCell()

    private let lineLockInputViewModel: LineLockInputViewModel
    
    init(confirmationFactory: ISendConfirmationFactory,
         feeSettingsFactory: ISendFeeSettingsFactory,
         viewModel: SendViewModel,
         availableBalanceViewModel: SendAvailableBalanceViewModel,
         amountInputViewModel: AmountInputViewModel,
         amountCautionViewModel: SendAmountCautionViewModel,
         recipientViewModel: RecipientAddressViewModel,
         memoViewModel: SendMemoInputViewModel,
         feeViewModel: SendFeeViewModel,
         feeWarningViewModel: ITitledCautionViewModel,
         lineLockInputViewModel: LineLockInputViewModel
    ) {
        self.lineLockInputViewModel = lineLockInputViewModel
        self.feeWarningViewModel = feeWarningViewModel
        
        feeCell = FeeCell(viewModel: feeViewModel, title: "fee_settings.fee".localized)
        
        lockedValueCell = LineLockInputCell(viewModel: lineLockInputViewModel, inputType: .amount)
        startMonthCell = LineLockInputCell(viewModel: lineLockInputViewModel, inputType: .startMonth)
        intervalMonthCell = LineLockInputCell(viewModel: lineLockInputViewModel, inputType: .intervalMonth)
        

        // timeLock cell
        if  let timeLockService = feeSettingsFactory.getTimeLockService() {
            let timeLockViewModel = TimeLockViewModel(service: timeLockService)
            self.timeLockViewModel = timeLockViewModel
            safeLockTimeCell = SafeDropDownListCell(viewModel: timeLockViewModel, title: "fee_settings.time_lock".localized)
        }
        
        super.init(
            confirmationFactory: confirmationFactory,
            viewModel: viewModel,
            availableBalanceViewModel: availableBalanceViewModel,
            amountInputViewModel: amountInputViewModel,
            amountCautionViewModel: amountCautionViewModel,
            recipientViewModel: recipientViewModel,
            memoViewModel: memoViewModel
        )

        

    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        lineLockTitleCell.contentText = "safe_lock.amount".localized
        
        feeCell.onOpenInfo = { [weak self] in
            self?.openInfo(title: "fee_settings.fee".localized, description: "fee_settings.fee.info".localized)
        }
        
        safeLockTimeCell?.showList = { [weak self] in self?.showList() }
        
        subscribe(disposeBag, lineLockInputViewModel.amountCautionDriver) {  [weak self] in
            self?.lockedValueCell.set(cautionType: $0?.type)
            self?.lockedValueCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, lineLockInputViewModel.startMonthCautionDriver) {  [weak self] in
            self?.startMonthCell.set(cautionType: $0?.type)
            self?.startMonthCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, lineLockInputViewModel.intervalMonthCautionDriver) {  [weak self] in
            self?.intervalMonthCell.set(cautionType: $0?.type)
            self?.intervalMonthCautionCell.set(caution: $0)
            self?.reloadTable()
        }
        
        subscribe(disposeBag, lineLockInputViewModel.lineLockDesDriver) {  [weak self] in
            self?.lineLockCautionCell.contentText = $0
            self?.reloadTable()
        }
        
        
        subscribe(disposeBag, feeWarningViewModel.cautionDriver) { [weak self] in
            self?.handle(caution: $0)
        }
        
        didLoad()
    }

    private func handle(caution: TitledCaution?) {
        feeCautionCell.isVisible = caution != nil

        if let caution = caution {
            feeCautionCell.bind(caution: caution)
        }

        reloadTable()
    }
    
    private func showList() {
        let alertController: UIViewController = AlertRouter.module(
                title: "fee_settings.time_lock".localized,
                viewItems: timeLockViewModel?.itemsList ?? []
        ) { [weak self] index in
            self?.timeLockViewModel?.onSelect(index)
        }
        present(alertController, animated: true)
    }

    private func openInfo(title: String, description: String) {
        let viewController = BottomSheetModule.description(title: title, text: description)
        present(viewController, animated: true)
    }

    var feeSection: SectionProtocol {
        Section(
                id: "fee",
                headerState: .margin(height: .margin12),
                rows: [
                    StaticRow(
                            cell: feeCell,
                            id: "fee",
                            height: .heightDoubleLineCell
                    )
                ]
        )
    }
    
    var feeWarningSection: SectionProtocol {
        Section(
                id: "fee-warning",
                headerState: .margin(height: .margin12),
                rows: [
                    StaticRow(
                            cell: feeCautionCell,
                            id: "fee-warning",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.feeCautionCell.cellHeight(containerWidth: containerWidth) ?? 0
                            }
                    )
                ]
        )
    }
    
    var safeLockTimeSection: SectionProtocol? {
        guard let safeLockTimeCell = safeLockTimeCell else { return nil }
        return Section(
                id: "safe-time-lock",
                headerState: .margin(height: .margin12),
                rows: [
                    StaticRow(
                            cell: safeLockTimeCell,
                            id: "safe-time-lock-cell",
                            height: .heightCell56
                    )
                ]
        )
    }
    

    var lineLockSection: SectionProtocol {
        Section(
                id: "amount",
                headerState: .margin(height: .margin8),
                rows: [
                    StaticRow(
                            cell: lockedValueCell,
                            id: "amount-input",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.lockedValueCell.height(containerWidth: containerWidth) ?? 0
                            }
                    ),
                    StaticRow(
                            cell: lockedValueCautionCell,
                            id: "amount-warning",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.lockedValueCautionCell.height(containerWidth: containerWidth) ?? 0
                            }
                    ),
                    StaticRow(
                            cell: startMonthCell,
                            id: "startMonth-input",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.startMonthCell.height(containerWidth: containerWidth) ?? 0
                            }
                    ),
                    StaticRow(
                            cell: startMonthCautionCell,
                            id: "startMonth-warning",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.startMonthCautionCell.height(containerWidth: containerWidth) ?? 0
                            }
                    ),
                    StaticRow(
                            cell: intervalMonthCell,
                            id: "interval-input",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.intervalMonthCell.height(containerWidth: containerWidth) ?? 0
                            }
                    ),
                    StaticRow(
                            cell: intervalMonthCautionCell,
                            id: "interval-warning",
                            dynamicHeight: { [weak self] containerWidth in
                                self?.intervalMonthCautionCell.height(containerWidth: containerWidth) ?? 0
                            }
                    )
                ]
        )
    }
    
    var lineLockTitleSection: SectionProtocol {
        Section(
                id: "lineLock-title",
                headerState: .margin(height: .margin2),
                rows: [
                    StaticRow(
                            cell: lineLockTitleCell,
                            id: "lineLock-title",
                            height: .heightSingleLineCell
                    )
                ]
        )
    }
    
    var lineLockWarningSection: SectionProtocol {
        Section(
                id: "lineLock-des",
                headerState: .margin(height: .margin4),
                rows: [
                    StaticRow(
                            cell: lineLockCautionCell,
                            id: "lineLock-des",
                            dynamicHeight: { [weak self] containerWidth in
                                TextCell.height(containerWidth: containerWidth, text: self?.lineLockInputViewModel.lineLockDes ?? "")
                            }
                    )
                ]
        )
    }

    
    override func buildSections() -> [SectionProtocol] {
        var sections = [availableBalanceSection, lineLockTitleSection, amountSection, recipientSection, lineLockSection, feeSection,]
        sections.append(contentsOf: [feeWarningSection, lineLockWarningSection, buttonSection])
        
        if let lockTimeSection = safeLockTimeSection {
            let index = sections.index(before: sections.endIndex)
            sections.insert(lockTimeSection, at: index)
        }
        return sections
    }

}



