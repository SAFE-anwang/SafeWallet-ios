import BigInt
import EvmKit
import Combine
import Foundation
import MarketKit

// The Standard tab of PreSendView: a direct transfer to the recipient, with memo and destination tag.
public class PreSendViewModel: BasePreSendViewModel {
    var isActiveTab = true
    lazy var allowanceHandler = PreSendAllowanceHandler(token: token)
    @Published public var selectedTimeLock: SafeTimeLockOption = .none {
        didSet {
            allowanceHandler.resetState()
            sendData = nil
            cautions = []
            syncSendData()
        }
    }
    public var timeLockItems: [SafeTimeLockOption] { SafeTimeLockOption.allCases }
    public var minTimeLockCoinValue: Decimal { 1 }
    public var isSupportedTimeLockToken: Bool { timeLockToken != nil }

    @Published var memoType: MemoType = .none
    @Published var destinationTagState: DestinationTagState = .hidden

    @Published var memo: String = "" {
        didSet {
            syncSendData()
        }
    }

    @Published var destinationTag: String = "" {
        didSet {
            syncSendData()
        }
    }

    public convenience init(wallet: Wallet, predefinedAddress: ResolvedAddress?, amount: Decimal?, memo: String?, customDecimals: Int? = nil) {
        self.init(
            wallet: wallet,
            handler: SendHandlerFactory.preSendHandler(wallet: wallet, address: predefinedAddress),
            spendStepHandler: SpendStepHandlerFactory.handler(wallet: wallet, purpose: .send),
            predefinedAddress: predefinedAddress,
            amount: amount,
            memo: memo,
            customDecimals: customDecimals
        )
    }

    public init(wallet: Wallet, handler: IPreSendHandler?, spendStepHandler: ISpendStepHandler? = nil, predefinedAddress: ResolvedAddress?, amount: Decimal?, memo: String?, destinationTag: String? = nil, customDecimals: Int? = nil) {
        super.init(wallet: wallet, handler: handler, spendStepHandler: spendStepHandler, predefinedAddress: predefinedAddress, amount: amount, initialInputToken: wallet.token, customDecimals: customDecimals)

        if let handler {
            destinationTagState = handler.destinationTagState

            handler.destinationTagStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    self?.destinationTagState = $0
                    self?.syncSendData()
                }
                .store(in: &cancellables)
        }

        syncMemoType()

        if let memo {
            self.memo = memo
        }

        if let destinationTag {
            self.destinationTag = destinationTag
        }

        // Explicit: `memo`'s didSet does not fire from this class's own init, and the base init applied
        // the amount before memo type and destination tag state were known.
        syncSendData()
    }

    // Only the Standard tab tells the shared handler about the recipient: the handler's
    // address-dependent state (e.g. the XRP destination tag) follows the Standard address.
    override func didChangeAddress() {
        handler?.set(address: resolvedAddress?.address)
        syncMemoType()
        destinationTag = ""
    }

    override func syncSendData() {
        guard isActiveTab else {
            sendData = nil
            return
        }
        guard let amount else {
            sendData = nil
            return
        }

        guard let resolvedAddress else {
            sendData = nil
            cautions = []
            return
        }

        guard let handler else {
            sendData = nil
            return
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)
        let memo = memoType != .none && !trimmedMemo.isEmpty ? trimmedMemo : nil

        synceTimeLock()
        if selectedTimeLock != .none {
            guard isSupportedTimeLockToken, amount >= minTimeLockCoinValue else {
                sendData = nil
                return
            }
            if case .some(.src20) = (handler as? EvmPreSendHandler)?.timeLock?.token {
                sendData = nil
                let timeLockSelection = selectedTimeLock
                allowanceHandler.getAllowanceState(amount: amount, availableBalance: availableBalance ?? 0) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.isActiveTab, self.amount == amount, self.resolvedAddress?.address == resolvedAddress.address,
                              self.selectedTimeLock == timeLockSelection else { return }
                        self.objectWillChange.send()
                        self.updateSendData(handler: handler, amount: amount, address: resolvedAddress.address, memo: memo)
                    }
                }
                return
            }
        }
        updateSendData(handler: handler, amount: amount, address: resolvedAddress.address, memo: memo)
    }

    private func updateSendData(handler: IPreSendHandler, amount: Decimal, address: String, memo: String?) {
        if selectedTimeLock != .none, case .some(.src20) = (handler as? EvmPreSendHandler)?.timeLock?.token {
            switch allowanceHandler.allowanceState {
            case .allowed?, .notRequired?: break
            default:
                sendData = nil
                return
            }
        }
        let result = handler.sendData(amount: amount, address: address, memo: memo, destinationTagInput: destinationTag)

        switch result {
        case let .valid(sendData):
            self.sendData = ExtendedSendData(sendData: sendData, address: address)
            cautions = []
        case let .invalid(cautions):
            sendData = nil
            self.cautions = cautions
        }
    }

    override var formError: String? {
        if selectedTimeLock != .none, let amount, amount < minTimeLockCoinValue {
            return "send.min_lock_amount".localized("\(minTimeLockCoinValue)")
        }
        return isMemoTooLong ? "send.memo.too_long".localized : nil
    }

    // Shown as it came and blocking the send, never cut to fit; measured as sent, without edge whitespace
    override var buttonState: PreSendButtonState {
        let state = super.buttonState
        guard selectedTimeLock != .none, isReachable, adapterState?.isSynced == true,
              let amount, let availableBalance, amount <= availableBalance,
              amount >= minTimeLockCoinValue, resolvedAddress != nil, formError == nil,
              let custom = allowanceHandler.allowanceState?.customButtonState else { return state }
        return PreSendButtonState(title: custom.title, disabled: custom.disabled, showProgress: custom.showProgress, progress: nil, style: .yellow)
    }

    private var isMemoTooLong: Bool {
        guard let memoMaxBytes else {
            return false
        }

        return memo.trimmingCharacters(in: .whitespaces).utf8.count > memoMaxBytes
    }

    private var memoMaxBytes: Int? {
        memoType == .none ? nil : wallet.token.blockchainType.memoMaxBytes
    }

    private func syncMemoType() {
        guard let handler else {
            memoType = .none
            return
        }

        memoType = handler.memoType(address: resolvedAddress?.address)
    }
}

extension PreSendViewModel {
    private var timeLockToken: TimeLock.Token? {
        if token.isSafe4Native {
            return .native
        }

        guard token.blockchain.type == .safe4,
              case let .eip20(address) = token.type,
              token.isSafe4ETH || token.isSafe4BSC || token.isSafe4POL || token.isSafe4SRC ||
                  (token.coin.uid.isSafeFourCustomCoin && SRC20SyncManager.logo(coinUid: token.coin.uid.lowercased()) != nil),
              let contract = try? EvmKit.Address(hex: address)
        else {
            return nil
        }

        return .src20(contract: contract)
    }

    func synceTimeLock() {
        switch handler  {
        case let handler as EvmPreSendHandler:
            var timeLock: TimeLock?

            if selectedTimeLock == .none {
                timeLock = nil
            } else if let days = selectedTimeLock.days {
                guard let amount, let evmAmount = BigUInt(amount.hs.roundedString(decimal: token.decimals)) else {
                    return
                }
                if let token = timeLockToken {
                    timeLock = TimeLock(token: token, lockDays: days, value: evmAmount)
                }
            }
            handler.timeLock = timeLock
        default: ()
        }
    }
}
