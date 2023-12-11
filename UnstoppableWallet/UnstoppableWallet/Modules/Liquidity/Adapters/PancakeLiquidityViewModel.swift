import Foundation
import RxSwift
import RxCocoa
import UniswapKit
import CurrencyKit
import EvmKit
import MarketKit
class PancakeLiquidityViewModel {
    private let disposeBag = DisposeBag()

    public let service: PancakeLiquidityService
    public let tradeService: PancakeLiquidityTradeService
    public let switchService: AmountTypeSwitchService
    private let currencyKit: CurrencyKit.Kit
    private let allowanceServiceA: LiquidityAllowanceService
    private let pendingAllowanceServiceA: LiquidityPendingAllowanceService
    private let allowanceServiceB: LiquidityAllowanceService
    private let pendingAllowanceServiceB: LiquidityPendingAllowanceService

    private let viewItemHelper: LiquidityViewItemHelper

    private var availableBalanceRelay = BehaviorRelay<String?>(value: nil)
    private var priceImpactRelay = BehaviorRelay<PancakeLiquidityModule.PriceImpactViewItem?>(value: nil)
    private var buyPriceRelay = BehaviorRelay<SwapPriceCell.PriceViewItem?>(value: nil)
    private var countdownTimerRelay = BehaviorRelay<Float>(value: 1)
    private var isLoadingRelay = BehaviorRelay<Bool>(value: false)
    private var swapErrorRelay = BehaviorRelay<String?>(value: nil)
    private var tradeViewItemRelay = BehaviorRelay<TradeViewItem?>(value: nil)
    private var settingsViewItemRelay = BehaviorRelay<SettingsViewItem?>(value: nil)
    private var proceedActionRelay = BehaviorRelay<ActionState>(value: .hidden)
    private var revokeWarningRelay = BehaviorRelay<String?>(value: nil)
    private var revokeActionRelay = BehaviorRelay<ActionState>(value: .hidden)
    private var approveActionRelay = BehaviorRelay<ActionState>(value: .hidden)
    private var approveStepRelay = BehaviorRelay<SwapModule.ApproveStepState>(value: .notApproved)
    private var openConfirmRelay = PublishRelay<SendEvmData>()
    private var amountTypeIndexRelay = BehaviorRelay<Int>(value: 0)
    private var isAmountToggleAvailableRelay = BehaviorRelay<Bool>(value: false)

    private var openRevokeRelay = PublishRelay<LiquidityAllowanceService.ApproveData>()
    private var openApproveRelay = PublishRelay<LiquidityAllowanceService.ApproveData>()

    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "io.horizontalsystems.unstoppable.swap_view_model")

    init(service: PancakeLiquidityService, tradeService: PancakeLiquidityTradeService, switchService: AmountTypeSwitchService, allowanceServiceA: LiquidityAllowanceService, pendingAllowanceServiceA: LiquidityPendingAllowanceService, allowanceServiceB: LiquidityAllowanceService, pendingAllowanceServiceB: LiquidityPendingAllowanceService,currencyKit: CurrencyKit.Kit, viewItemHelper: LiquidityViewItemHelper) {
        self.service = service
        self.tradeService = tradeService
        self.switchService = switchService
        self.allowanceServiceA = allowanceServiceA
        self.pendingAllowanceServiceA = pendingAllowanceServiceA
        
        self.allowanceServiceB = allowanceServiceB
        self.pendingAllowanceServiceB = pendingAllowanceServiceB
        self.currencyKit = currencyKit
        self.viewItemHelper = viewItemHelper

        subscribeToService()

        sync(state: service, pendingAllowanceService: pendingAllowanceServiceA)
        sync(state: service, pendingAllowanceService: pendingAllowanceServiceB)
        
        sync(errors: service.errors)
        sync(tradeState: tradeService.state)
    }

    private func subscribeToService() {
        subscribe(disposeBag, tradeService.stateObservable) { [weak self] in self?.sync(tradeState: $0) }
        subscribe(scheduler, disposeBag, service.stateObservable) { [weak self] _ in self?.handleObservable() }
        subscribe(disposeBag, tradeService.countdownTimerObservable) { [weak self] in self?.handle(countdownValue: $0) }
        subscribe(scheduler, disposeBag, service.errorsObservable) { [weak self] in self?.handleObservable(errors: $0) }
        subscribe(disposeBag, service.balanceInObservable) { [weak self] in self?.sync(fromBalance: $0) }
        subscribe(scheduler, disposeBag, tradeService.stateObservable) { [weak self] in self?.sync(tradeState: $0) }
        subscribe(scheduler, disposeBag, tradeService.settingsObservable) { [weak self] in self?.sync(swapSettings: $0) }
        subscribe(scheduler, disposeBag, pendingAllowanceServiceA.stateObservable) { [weak self] _ in self?.handleObservable() }
        subscribe(scheduler, disposeBag, pendingAllowanceServiceB.stateObservable) { [weak self] _ in self?.handleObservable() }
        subscribe(disposeBag, switchService.amountTypeObservable) { [weak self] in self?.sync(amountType: $0) }
        subscribe(disposeBag, switchService.toggleAvailableObservable) { [weak self] in self?.sync(toggleAvailable: $0) }

        sync(fromBalance: service.balanceIn)
        sync(amountType: switchService.amountType)
        sync(toggleAvailable: switchService.toggleAvailable)
    }

    private func sync(state service: PancakeLiquidityService, pendingAllowanceService: LiquidityPendingAllowanceService) {
        let state = service.state

        isLoadingRelay.accept(state == .loading)
        syncProceedAction(service: service, pendingAllowanceService: pendingAllowanceService)
    }

    private func handleObservable(errors: [Error]? = nil) {
        if let errors = errors {
            sync(errors: errors)
        }

        syncProceedAction(service: service, pendingAllowanceService: pendingAllowanceServiceA)
        syncApproveAction(service: service, pendingAllowanceService: pendingAllowanceServiceA)
        
        syncProceedAction(service: service, pendingAllowanceService: pendingAllowanceServiceB)
        syncApproveAction(service: service, pendingAllowanceService: pendingAllowanceServiceB)
    }

    private func handle(countdownValue: Float) {
        countdownTimerRelay.accept(countdownValue)
    }

    private func sync(fromBalance: Decimal?) {
        guard let token = tradeService.tokenIn, let balance = fromBalance else {
            availableBalanceRelay.accept(nil)
            return
        }

        let coinValue = CoinValue(kind: .token(token: token), value: balance)
        availableBalanceRelay.accept(ValueFormatter.instance.formatFull(coinValue: coinValue))
    }
    
    private func sync(errors: [Error]? = nil) {
       let errors = errors ?? service.errors

        let filtered = errors.filter { error in
            switch error {
            case let error as UniswapKit.Kit.TradeError: return error != .zeroAmount
            case _ as EvmFeeModule.GasDataError: return false
            case _ as SwapModule.SwapError: return false
            default: return true
            }
        }

        swapErrorRelay.accept(filtered.first?.convertedError.smartDescription)
    }

    private func sync(tradeState: PancakeLiquidityTradeService.State) {
        var loading = false
        switch tradeState {
        case .loading:
            loading = true
        case .ready(let trade):
            if let executionPrice = trade.tradeData.executionPrice, !executionPrice.isZero {
                let prices = viewItemHelper.sortedPrices(
                        executionPrice: executionPrice,
                        invertedPrice: trade.tradeData.executionPriceInverted ?? (1 / executionPrice),
                        tokenIn: tradeService.tokenIn, tokenOut: tradeService.tokenOut)
                buyPriceRelay.accept(SwapPriceCell.PriceViewItem(price: prices?.0, revertedPrice: prices?.1))
            } else {
                buyPriceRelay.accept(nil)
            }
            priceImpactRelay.accept(viewItemHelper.priceImpactViewItem(priceImpact: trade.tradeData.priceImpact, impactLevel: trade.impactLevel))
        case .notReady:
            buyPriceRelay.accept(nil)
            priceImpactRelay.accept(nil)
        }

        isLoadingRelay.accept(loading)
        handleObservable()
    }

    private func sync(swapSettings: UniswapSettings) {
        settingsViewItemRelay.accept(settingsViewItem(settings: swapSettings))
    }

    private func syncProceedAction(service: PancakeLiquidityService, pendingAllowanceService: LiquidityPendingAllowanceService) {
        var actionState = ActionState.disabled(title: "swap.proceed_button".localized)

        if case .ready = service.state {
            actionState = .enabled(title: "swap.proceed_button".localized)
        } else if let error = service.errors.compactMap({ $0 as? SwapModule.SwapError}).first {
            switch error {
            case .noBalanceIn: actionState = .disabled(title: "swap.not_available_button".localized)
            case .insufficientBalanceIn: actionState = .disabled(title: "swap.button_error.insufficient_balance".localized)
            case .needRevokeAllowance:
                switch tradeService.state {
                case .notReady: ()
                default: actionState = .hidden
                }
            default: ()
            }
        } else if case .revoking = pendingAllowanceService.state {
            actionState = .hidden
        }
        proceedActionRelay.accept(actionState)
    }

    private func syncApproveAction(service: PancakeLiquidityService, pendingAllowanceService: LiquidityPendingAllowanceService) {
        
        var approveAction: ActionState = .hidden
        var revokeAction: ActionState = .hidden
        var revokeWarning: String?
        let approveStep: SwapModule.ApproveStepState

        for error in service.errors {
            if let allowance = (error as? SwapModule.SwapError)?.revokeAllowance {
                revokeWarning = "swap.revoke_warning".localized(ValueFormatter.instance.formatFull(coinValue: allowance) ?? "n/a".localized)
            }
        }
        if case .pending = pendingAllowanceService.state {
            revokeWarning = nil
            approveAction = .disabled(title: "swap.approving_button".localized)
            approveStep = .approving
        } else if case .revoking = pendingAllowanceService.state {
            revokeWarning = nil
            revokeAction = .disabled(title: "swap.revoking_button".localized)
            approveStep = .revoking
        } else if case .notReady = tradeService.state {
            revokeWarning = nil
            approveStep = .notApproved
        } else if service.errors.contains(where: { .insufficientBalanceIn == $0 as? SwapModule.SwapError }) {
            approveStep = .notApproved
        } else if revokeWarning != nil {
            revokeAction = .enabled(title: "button.revoke".localized)
            approveStep = .revokeRequired
        } else if service.errors.contains(where: { .insufficientAllowance == $0 as? SwapModule.SwapError }) {
            approveAction = .enabled(title: "button.approve".localized)
            approveStep = .approveRequired
        } else if case .approved = pendingAllowanceService.state {
            approveAction = .disabled(title: "button.approve".localized)
            approveStep = .approved
        } else {
            revokeWarning = nil
            approveStep = .notApproved
        }

        revokeWarningRelay.accept(revokeWarning)
        revokeActionRelay.accept(revokeAction)
        approveActionRelay.accept(approveAction)
        approveStepRelay.accept(approveStep)
    }
    
    private func settingsViewItem(settings: UniswapSettings) -> SettingsViewItem {
        SettingsViewItem(slippage: viewItemHelper.slippage(settings.allowedSlippage),
            deadline: viewItemHelper.deadline(settings.ttl),
            recipient: settings.recipient?.title)
    }

    private func sync(amountType: AmountTypeSwitchService.AmountType) {
        switch amountType {
        case .coin: amountTypeIndexRelay.accept(0)
        case .currency: amountTypeIndexRelay.accept(1)
        }
    }

    private func sync(toggleAvailable: Bool) {
        isAmountToggleAvailableRelay.accept(toggleAvailable)
    }

}

extension PancakeLiquidityViewModel {

    var amountTypeSelectorItems: [String] {
        ["swap.amount_type.coin".localized, currencyKit.baseCurrency.code]
    }

    var amountTypeIndexDriver: Driver<Int> {
        amountTypeIndexRelay.asDriver()
    }

    var isAmountTypeAvailableDriver: Driver<Bool> {
        isAmountToggleAvailableRelay.asDriver()
    }

    var availableBalanceDriver: Driver<String?> {
        availableBalanceRelay.asDriver()
    }

    var buyPriceDriver: Driver<SwapPriceCell.PriceViewItem?> {
        buyPriceRelay.asDriver()
    }

    var countdownTimerDriver: Driver<Float> {
        countdownTimerRelay.asDriver()
    }

    var amountInDriver: Driver<Decimal> {
        tradeService.amountInObservable.asDriver(onErrorJustReturn: 0)
    }

    var isLoadingDriver: Driver<Bool> {
        isLoadingRelay.asDriver()
    }

    var swapErrorDriver: Driver<String?> {
        swapErrorRelay.asDriver()
    }

    var priceImpactDriver: Driver<PancakeLiquidityModule.PriceImpactViewItem?> {
        priceImpactRelay.asDriver()
    }

    var settingsViewItemDriver: Driver<SettingsViewItem?> {
        settingsViewItemRelay.asDriver()
    }

    var proceedActionDriver: Driver<ActionState> {
        proceedActionRelay.asDriver()
    }

    var revokeWarningDriver: Driver<String?> {
        revokeWarningRelay.asDriver()
    }

    var revokeActionDriver: Driver<ActionState> {
        revokeActionRelay.asDriver()
    }

    var approveActionDriver: Driver<ActionState> {
        approveActionRelay.asDriver()
    }

    var approveStepDriver: Driver<SwapModule.ApproveStepState> {
        approveStepRelay.asDriver()
    }

    var openRevokeSignal: Signal<LiquidityAllowanceService.ApproveData> {
        openRevokeRelay.asSignal()
    }

    var openApproveSignal: Signal<LiquidityAllowanceService.ApproveData> {
        openApproveRelay.asSignal()
    }

    var openConfirmSignal: Signal<SendEvmData> {
        openConfirmRelay.asSignal()
    }

    var dexName: String {
        service.dex.provider.rawValue
    }

    func onTapSwitch() {
        tradeService.switchCoins()
    }

    func onChangeAmountType(index: Int) {
        switchService.toggle()
    }
    
    func onTapRevoke() {

//        guard let approveData = service.approveData(amount: 0, token: token) else {
//            return
//        }
//
//        openRevokeRelay.accept(approveData)
    }

    func onTapApprove() {
//        guard let approveData = service.approveData(token: token) else {
//            return
//        }
//
//        openApproveRelay.accept(approveData)
    }

    func didApprove() {
        pendingAllowanceServiceA.syncAllowance()
        pendingAllowanceServiceB.syncAllowance()
    }

    func onTapProceed() {
        guard case .ready(let transactionData) = service.state else {
            return
        }
        
        guard case let .ready(trade) = tradeService.state else {
            return
        }
        
        let swapInfo = SendEvmData.PancakeLiquidityInfo(
                estimatedOut: tradeService.amountOut,
                estimatedIn: tradeService.amountIn,
                slippage: viewItemHelper.slippage(tradeService.settings.allowedSlippage),
                deadline: viewItemHelper.deadline(tradeService.settings.ttl),
                recipientDomain: tradeService.settings.recipient?.domain,
                price: viewItemHelper.sortedPrices(
                        executionPrice: trade.tradeData.executionPrice,
                        invertedPrice: trade.tradeData.executionPriceInverted,
                        tokenIn: tradeService.tokenIn,
                        tokenOut: tradeService.tokenOut)?.0,
                priceImpact: viewItemHelper.priceImpactViewItem(priceImpact: trade.tradeData.priceImpact, impactLevel: trade.impactLevel),
                gasPrice: nil
        )

        var impactWarnings = [Warning]()
        var impactErrors = [Error]()

        switch trade.impactLevel {
        case .warning:  impactWarnings = [PancakeLiquidityModule.LiquidityWarning.highPriceImpact]
        case .forbidden:  impactErrors = [PancakeLiquidityModule.LiquidityError.forbiddenPriceImpact(provider: "PancakeSwap")] // we can use url from dex
        default: ()
        }
        let sendEvmData = SendEvmData(
                transactionData: transactionData,
                additionalInfo: .pancakeLiquidity(info: swapInfo),
                warnings: impactWarnings,
                errors: impactErrors
        )

        openConfirmRelay.accept(sendEvmData)
    }

}

extension PancakeLiquidityViewModel {

    struct TradeViewItem {
        let executionPrice: String?
        let executionPriceInverted: String?
        let priceImpact: PancakeLiquidityModule.PriceImpactViewItem?
        let guaranteedAmount: PancakeLiquidityModule.GuaranteedAmountViewItem?
    }

    struct SettingsViewItem {
        let slippage: String?
        let deadline: String?
        let recipient: String?
    }

    enum ActionState {
        case hidden
        case enabled(title: String)
        case disabled(title: String)
    }

}
