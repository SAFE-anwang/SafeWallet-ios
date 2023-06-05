//  SafeTimeLockDataSource.swift

import UIKit
import ThemeKit
import SnapKit
import SectionsTableView
import RxSwift
import RxCocoa
import ComponentKit

class SafeTimeLockDataSource {
    private let viewModel: TimeLockViewModel
    private let disposeBag = DisposeBag()

    private let safeLockTimeCell: SafeDropDownListCell

    weak var tableView: SectionsTableView?
    var onOpenInfo: ((String, String) -> ())? = nil
    var present: ((UIViewController) -> ())? = nil
    var onUpdateAlteredState: (() -> ())? = nil
    var onCaution: ((TitledCaution?) -> ())? = nil

    init(viewModel: TimeLockViewModel) {
        self.viewModel = viewModel
        safeLockTimeCell = SafeDropDownListCell(viewModel: viewModel, title: "fee_settings.time_lock".localized)
    }

    func viewDidLoad() {
        safeLockTimeCell.showList = { [weak self] in self?.showList() }
        subscribe(disposeBag, viewModel.alteredStateSignal) { [weak self] in self?.onUpdateAlteredState?() }
    }

    private func showList() {
        let alertController: UIViewController = AlertRouter.module(
                title: "fee_settings.time_lock".localized,
                viewItems: viewModel.itemsList
        ) { [weak self] index in
            self?.viewModel.onSelect(index)
        }

        present?(alertController)
    }

}

extension SafeTimeLockDataSource: ISendSettingsDataSource {

    var altered: Bool {
        viewModel.altered
    }

    var buildSections: [SectionProtocol] {

        return [
            Section(
                    id: "safe-time-lock",
                    headerState: .margin(height: .margin24),
                    rows: [
                        StaticRow(
                                cell: safeLockTimeCell,
                                id: "safe-time-lock-cell",
                                height: .heightDoubleLineCell
                        )
                    ]
            )
        ]
    }

    func onTapReset() {
        viewModel.reset()
    }

}
