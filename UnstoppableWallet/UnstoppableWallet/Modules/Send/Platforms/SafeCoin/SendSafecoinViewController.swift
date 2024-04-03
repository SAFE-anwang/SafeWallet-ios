import RxCocoa
import RxSwift
import SectionsTableView
import SnapKit
import ThemeKit
import UIKit

class SendSafecoinViewController: BaseSendViewController {
    private let disposeBag = DisposeBag()

    private let feeWarningViewModel: ITitledCautionViewModel

    private let feeCell: FeeCell
    private let feeCautionCell = TitledHighlightedDescriptionCell()
    
    private var safeLockTimeCell: SafeDropDownListCell?
    private var timeLockViewModel: TimeLockViewModel?

    init(confirmationFactory: ISendConfirmationFactory,
         feeSettingsFactory: ISendFeeSettingsFactory,
         viewModel: SendViewModel,
         availableBalanceViewModel: SendAvailableBalanceViewModel,
         amountInputViewModel: AmountInputViewModel,
         amountCautionViewModel: SendAmountCautionViewModel,
         recipientViewModel: RecipientAddressViewModel,
         memoViewModel: SendMemoInputViewModel,
         feeViewModel: SendFeeViewModel,
         feeWarningViewModel: ITitledCautionViewModel)
    {
        self.feeWarningViewModel = feeWarningViewModel

        feeCell = FeeCell(viewModel: feeViewModel, title: "fee_settings.fee".localized)
        
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

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        feeCell.onOpenInfo = { [weak self] in
            self?.openInfo(title: "fee_settings.fee".localized, description: "fee_settings.fee.info".localized)
        }
        
        safeLockTimeCell?.showList = { [weak self] in self?.showList() }

        subscribe(disposeBag, feeWarningViewModel.cautionDriver) { [weak self] in
            self?.handle(caution: $0)
        }

        didLoad()
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


    private func handle(caution: TitledCaution?) {
        feeCautionCell.isVisible = caution != nil

        if let caution {
            feeCautionCell.bind(caution: caution)
        }

        reloadTable()
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
                    height: .heightCell48
                ),
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
                ),
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

    override func buildSections() -> [SectionProtocol] {
        var sections = super.buildSections()
        sections.append(contentsOf: [
            memoSection,
            feeSection,
            feeWarningSection,
            buttonSection,
        ])
                
        if let lockTimeSection = safeLockTimeSection {
            let index = sections.index(before: sections.endIndex)
            sections.insert(lockTimeSection, at: index)
        }

        return sections
    }
}
