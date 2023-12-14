/*
import UIKit
import ThemeKit
import UniswapKit
import HUD
import RxSwift
import RxCocoa
import SectionsTableView
import ComponentKit

class LiquidityRecordDataSource {
    private static let levelColors: [UIColor] = [.themeRemus, .themeJacob, .themeLucian, .themeLucian]
    
    private let disposeBag = DisposeBag()
    
    private let viewModel: LiquidityRecordViewModel
    private let allowanceViewModel: LiquidityAllowanceViewModel

    private let buttonStackCell = StackViewCell()
    
    private let revokeButton = PrimaryButton()
    private let approve1Button = PrimaryButton()
    
    private let proceedButton = PrimaryButton()
    private let proceed2Button = PrimaryButton()
    
    var onOpen: ((_ viewController: UIViewController, _ viaPush: Bool) -> ())? = nil
    var onReload: (() -> ())? = nil
    
    weak var tableView: UITableView?
    
    private var emptyAmountIn: Bool = true
    
    private var lastBuyPrice: SwapPriceCell.PriceViewItem?
    private var lastAllowance: String?
    private var lastAvailableBalance: String?
    private var lastPriceImpact: PancakeLiquidityModule.PriceImpactViewItem?
    private var error: String?
    
    init(viewModel: LiquidityRecordViewModel, allowanceViewModel: LiquidityAllowanceViewModel) {
        self.viewModel = viewModel
        self.allowanceViewModel = allowanceViewModel
        
        initCells()
    }
    
    func initCells() {
        revokeButton.set(style: .yellow)
        revokeButton.addTarget(self, action: #selector((onTapRevokeButton)), for: .touchUpInside)
        buttonStackCell.add(view: revokeButton)

        approve1Button.addTarget(self, action: #selector((onTapApproveButton)), for: .touchUpInside)
        buttonStackCell.add(view: approve1Button)

        proceedButton.set(style: .yellow)
        proceedButton.addTarget(self, action: #selector((onTapProceedButton)), for: .touchUpInside)
        buttonStackCell.add(view: proceedButton)

        proceed2Button.set(style: .yellow, accessoryType: .icon(image: UIImage(named: "numbers_2_24")))
        proceed2Button.addTarget(self, action: #selector((onTapProceedButton)), for: .touchUpInside)
        buttonStackCell.add(view: proceed2Button)

        subscribeToViewModel()
    }
    
    private func subscribeToViewModel() {
        subscribe(disposeBag, viewModel.availableBalanceDriver) { [weak self] in self?.handle(balance: $0) }
        subscribe(disposeBag, viewModel.priceImpactDriver) { [weak self] in self?.handle(priceImpact: $0) }
        subscribe(disposeBag, viewModel.buyPriceDriver) { [weak self] in self?.handle(buyPrice: $0) }
        subscribe(disposeBag, viewModel.countdownTimerDriver) { [weak self] in self?.handle(countDownTimer: $0) }
        subscribe(disposeBag, viewModel.amountInDriver) { [weak self] in self?.handle(amountIn: $0) }

        subscribe(disposeBag, viewModel.isLoadingDriver) { [weak self] in self?.handle(loading: $0) }
        subscribe(disposeBag, viewModel.swapErrorDriver) { [weak self] in self?.handle(error: $0) }
        subscribe(disposeBag, viewModel.proceedActionDriver) { [weak self] in self?.handle(proceedActionState: $0) }
        subscribe(disposeBag, viewModel.revokeWarningDriver) { [weak self] in self?.handle(revokeWarning: $0) }
        subscribe(disposeBag, viewModel.revokeActionDriver) { [weak self] in self?.handle(revokeActionState: $0) }
        subscribe(disposeBag, viewModel.approveActionDriver) { [weak self] in self?.handle(approveActionState: $0) }
        subscribe(disposeBag, viewModel.approveStepDriver) { [weak self] in self?.handle(approveStepState: $0) }

        subscribe(disposeBag, viewModel.openRevokeSignal) { [weak self] in self?.openRevoke(approveData: $0) }
        subscribe(disposeBag, viewModel.openApproveSignal) { [weak self] in self?.openApprove(approveData: $0) }
        subscribe(disposeBag, viewModel.openConfirmSignal) { [weak self] in self?.openConfirm(sendData: $0) }
        subscribe(disposeBag, viewModel.amountTypeIndexDriver) { [weak self] in self?.settingsHeaderView.setSelector(index: $0) }
        subscribe(disposeBag, viewModel.isAmountTypeAvailableDriver) { [weak self] in self?.settingsHeaderView.setSelector(isEnabled: $0) }

        subscribe(disposeBag, allowanceViewModel.allowanceDriver) { [weak self] in self?.handle(allowance: $0)  }
    }
    
    private func handle(revokeActionState: PancakeLiquidityViewModel.ActionState) {
        handle(actionState: revokeActionState, button: revokeButton)
    }

    private func handle(error: String?) {
        self.error = error
        if let error = error {
//            errorCell.isVisible = true
//            errorCell.bind(caution: TitledCaution(title: "alert.error".localized, text: error, type: .error))
        } else {
//            errorCell.isVisible = false
        }

        onReload?()
    }

    private func handle(proceedActionState: PancakeLiquidityViewModel.ActionState) {
        handle(actionState: proceedActionState, button: proceedButton)
        handle(actionState: proceedActionState, button: proceed2Button)
    }

    private func handle(approveActionState: PancakeLiquidityViewModel.ActionState) {
        handle(actionState: approveActionState, button: approve1Button)
    }

    private func handle(actionState: PancakeLiquidityViewModel.ActionState, button: PrimaryButton) {
        switch actionState {
        case .hidden:
            button.isHidden = true
        case .enabled(let title):
            button.isHidden = false
            button.isEnabled = true
            button.setTitle(title, for: .normal)
        case .disabled(let title):
            button.isHidden = false
            button.isEnabled = false
            button.setTitle(title, for: .normal)
        }
    }

    private func handle(approveStepState: SwapModule.ApproveStepState) {
        let isApproving = approveStepState == .approving

        approve1Button.set(style: .gray, accessoryType: isApproving ? .spinner : .icon(image: UIImage(named: "numbers_1_24")))

        switch approveStepState {
        case .notApproved, .revokeRequired, .revoking:
            proceedButton.isHidden = false
            proceed2Button.isHidden = true
        default:
            proceedButton.isHidden = true
            proceed2Button.isHidden = false
        }

        onReload?()
    }
    
    @objc private func onTapRevokeButton() {
        //viewModel.onTapRevoke()
    }

    @objc private func onTapApproveButton() {
        //viewModel.onTapApprove()
    }

    @objc private func onTapProceedButton() {
        //viewModel.onTapProceed()
    }
}
*/
