import Combine
import EvmKit
import Foundation
import MarketKit
import RxSwift
import SwiftUI
import UIKit

// MARK: - SwiftUI 适配 ViewModel（RxSwift → Combine 桥接）

class MarketDappSendEvmConfirmationViewModel: ObservableObject {
    @Published var sectionViewItems: [SendEvmTransactionViewModel.SectionViewItem] = []
    @Published var cautions: [TitledCaution] = []
    @Published var sendEnabled: Bool = false
    @Published var isSending: Bool = false
    @Published var sendError: String?
    @Published var nonceValue: String = ""
    @Published var showNonce: Bool = false
    @Published var shouldDismiss: Bool = false
    
    // MARK: - 发送条件检查
    @Published var sendButtonState: SendButtonState = .disabled(reason: .initializing)
    @Published var disableReason: String = ""
    
    // 各项前置条件状态
    @Published var isNetworkConnected: Bool = true
    @Published var isBalanceSufficient: Bool = true
    @Published var isGasReady: Bool = false
    @Published var isNonceReady: Bool = false
    @Published var hasErrors: Bool = false
    @Published var hasWarnings: Bool = false

    private let transactionViewModel: SendEvmTransactionViewModel
    private let settingsViewModel: EvmSendSettingsViewModel
    private let disposeBag = DisposeBag()
    
    // ✅ 修复 #3: 使用 NSLock 保证 finished 标志的线程安全
    private let lock = NSLock()
    private var _finished: Bool = false
    private var finished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _finished
        }
        set {
            lock.lock()
            _finished = newValue
            lock.unlock()
        }
    }

    let onSendSuccess: (Data) -> Void
    let onSendFailed: (String) -> Void
    let onDismissed: (() -> Void)?  // ✅ 新增：页面关闭回调
    
    // MARK: - 信号订阅管理（实例级，防止局部 DisposeBag 导致信号丢失）
    private var signalDisposeBag = DisposeBag()
    
    // MARK: - 发送按钮状态枚举
    enum SendButtonState: Equatable {
        case enabled           // 可以发送
        case disabled(reason: DisableReason)  // 禁用及原因
        case sending          // 发送中
        
        var isEnabled: Bool {
            switch self {
            case .enabled: return true
            default: return false
            }
        }
    }
    
    enum DisableReason: String {
        case initializing = "Initializing..."
        case calculatingGas = "Calculating gas..."
        case insufficientBalance = "Insufficient balance"
        case networkError = "Network connection error"
        case hasErrors = "Please resolve errors first"
        case loadingNonce = "Loading nonce..."
        case notReady = "Transaction not ready"
    }
    
    // MARK: - 发送交易错误类型（借鉴 MultiSwap）
    enum SendError: LocalizedError {
        case invalidData
        case invalidTransactionData
        case noGasLimit
        case noGasPrice
        case noEvmKitWrapper
        case noActiveAccount
        case transactionNotReady
        case sendFailed(error: Error)
        
        var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Invalid transaction data"
            case .invalidTransactionData:
                return "Invalid transaction data"
            case .noGasLimit:
                return "Gas limit not available"
            case .noGasPrice:
                return "Gas price not available"
            case .noEvmKitWrapper:
                return "Wallet not available"
            case .noActiveAccount:
                return "No active account"
            case .transactionNotReady:
                return "Transaction not ready"
            case .sendFailed(let error):
                return error.localizedDescription
            }
        }
    }

    init(
        transactionViewModel: SendEvmTransactionViewModel,
        settingsViewModel: EvmSendSettingsViewModel,
        onSendSuccess: @escaping (Data) -> Void,
        onSendFailed: @escaping (String) -> Void,
        onDismissed: (() -> Void)? = nil
    ) {
        self.transactionViewModel = transactionViewModel
        self.settingsViewModel = settingsViewModel
        self.onSendSuccess = onSendSuccess
        self.onSendFailed = onSendFailed
        self.onDismissed = onDismissed

        // 订阅 RxSwift Observable 并转换为 Combine Published
        // 注意：所有 @Published 属性更新必须在主线程进行

        // 交易详情列表
        transactionViewModel.sectionViewItemsDriver
            .drive(onNext: { [weak self] items in
                DispatchQueue.main.async {
                    self?.sectionViewItems = items
                }
            })
            .disposed(by: disposeBag)

        // 警告/错误信息（合并了之前重复订阅和错误检查）
        transactionViewModel.cautionsDriver
            .drive(onNext: { [weak self] cautions in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.cautions = cautions
                    
                    let errors = cautions.filter { $0.type == .error }
                    let warnings = cautions.filter { $0.type == .warning }
                    self.hasErrors = !errors.isEmpty
                    self.hasWarnings = !warnings.isEmpty
                    self.updateSendButtonState()
                }
            })
            .disposed(by: disposeBag)

        // 发送按钮启用状态
        transactionViewModel.sendEnabledDriver
            .drive(onNext: { [weak self] enabled in
                DispatchQueue.main.async {
                    self?.sendEnabled = enabled
                    self?.updateSendButtonState()
                }
            })
            .disposed(by: disposeBag)
        
        // Gas 设置状态监控
        settingsViewModel.service.statusObservable
//            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .loading:
                    self.isGasReady = false
                    print("[SendConfirm] Gas calculation: loading...")
                case .completed(let fallibleTransaction):
                    self.isGasReady = true
                    let tx = fallibleTransaction.data
                    print("[SendConfirm] Gas calculation completed:")
                    print("  - gasLimit: \(tx.gasData.limit)")
                    print("  - gasPrice: \(tx.gasData.price)")
                    print("  - nonce: \(tx.nonce)")
                    print("  - warnings: \(fallibleTransaction.warnings.count)")
                    print("  - errors: \(fallibleTransaction.errors.count)")
                case .failed(let error):
                    self.isGasReady = false
                    print("[SendConfirm] Gas calculation failed:")
                    print("  - error: \(error.localizedDescription)")
                    print("  - details: \(error)")
                }
                self.updateSendButtonState()
            })
            .disposed(by: disposeBag)
        
        // Nonce 状态监听
        settingsViewModel.nonceViewModel.valueDriver
            .drive(onNext: { [weak self] nonce in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isNonceReady = nonce != nil
                    if let nonce {
                        self.nonceValue = "\(NSDecimalNumber(decimal: nonce).intValue)"
                    } else {
                        self.nonceValue = ""
                    }
                    self.updateSendButtonState()
                }
            })
            .disposed(by: disposeBag)

        // Nonce 显示状态
        settingsViewModel.nonceViewModel.alteredStateSignal
            .emit(onNext: { [weak self] in
                DispatchQueue.main.async {
                    self?.showNonce = true
                }
            })
            .disposed(by: disposeBag)
    }

    func send() {
        transactionViewModel.send()
    }
    
    // MARK: - 更新发送按钮状态（线程安全）
    func updateSendButtonState() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateSendButtonState()
            }
            return
        }

        if isSending {
            sendButtonState = .sending
            disableReason = "Sending transaction..."
            return
        }
        
        if !isNetworkConnected {
            sendButtonState = .disabled(reason: .networkError)
            disableReason = DisableReason.networkError.rawValue
            return
        }
        
        if !isGasReady {
            sendButtonState = .disabled(reason: .calculatingGas)
            disableReason = DisableReason.calculatingGas.rawValue
            return
        }
        
        if !isNonceReady {
            sendButtonState = .disabled(reason: .loadingNonce)
            disableReason = DisableReason.loadingNonce.rawValue
            return
        }
        
        if hasErrors {
            sendButtonState = .disabled(reason: .hasErrors)
            disableReason = DisableReason.hasErrors.rawValue
            return
        }
        
        if !isBalanceSufficient {
            sendButtonState = .disabled(reason: .insufficientBalance)
            disableReason = DisableReason.insufficientBalance.rawValue
            return
        }
        
        if !sendEnabled {
            sendButtonState = .disabled(reason: .notReady)
            disableReason = DisableReason.notReady.rawValue
            return
        }
        
        sendButtonState = .enabled
        disableReason = ""
    }
    
    /// 获取禁用原因的本地化描述
    func getDisableReasonText() -> String {
        switch sendButtonState {
        case .enabled:
            return ""
        case .sending:
            return "Sending..."
        case .disabled(let reason):
            return reason.rawValue
        }
    }

    /// 异步发送交易（用于 SlideButton）
    /// - Note: ✅ 修复 #1, #2, #3, #4: 使用局部 DisposeBag 防止内存泄漏，线程安全，完整清理
    func sendAsync() async throws {
        // 检查是否可以发送
        guard sendButtonState.isEnabled else {
            let reason = getDisableReasonText()
            throw NSError(domain: "SendError", code: -1, userInfo: [NSLocalizedDescriptionKey: reason])
        }
        
        // 更新状态为发送中
        isSending = true
        sendButtonState = .sending
        updateSendButtonState()
        
        return try await withCheckedThrowingContinuation { continuation in
            // 重置 finished 状态（线程安全）
            lock.lock()
            _finished = false
            lock.unlock()
            
            // ✅ 关键修复：使用实例级 DisposeBag，防止信号丢失
            // 局部 DisposeBag 会在方法返回时被释放，导致后续信号丢失
            // 实例级 DisposeBag 生命周期与 ViewModel 一致，确保信号不会丢失
            signalDisposeBag = DisposeBag()
            
            // 监听成功信号 - 确保在主线程处理
            transactionViewModel.sendSuccessSignal
                .emit(onNext: { [weak self] transactionHash in
                    DispatchQueue.main.async {
                        guard let self else {
                            continuation.resume(throwing: NSError(domain: "SendError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                            return
                        }
                        
                        // 使用锁检查 finished（线程安全）
                        self.lock.lock()
                        guard !self._finished else {
                            self.lock.unlock()
                            return
                        }
                        self._finished = true
                        self.lock.unlock()
                        
                        // 先通知 DApp（在 UI 动画之前）
                        print("[SendConfirm] Transaction success, notifying DApp...")
                        self.onSendSuccess(transactionHash)
                        
                        // 恢复 continuation（让 SlideButton 进入 success 状态并播放动画）
                        continuation.resume()
                    }
                })
                .disposed(by: signalDisposeBag)
            
            // 监听失败信号 - 确保在主线程处理
            transactionViewModel.sendFailedSignal
                .emit(onNext: { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self else {
                            continuation.resume(throwing: NSError(domain: "SendError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                            return
                        }
                        
                        // 使用锁检查 finished（线程安全）
                        self.lock.lock()
                        guard !self._finished else {
                            self.lock.unlock()
                            return
                        }
                        self._finished = true
                        self.lock.unlock()
                        
                        // 更新状态
                        self.isSending = false
                        self.sendError = error
                        HudHelper.instance.show(banner: .error(string: error))
                        self.onSendFailed(error)
                        self.updateSendButtonState()
                        
                        // 立即恢复 continuation（带错误），让 SlideButton 回到 start 状态
                        continuation.resume(throwing: NSError(domain: "SendError", code: -1, userInfo: [NSLocalizedDescriptionKey: error]))
                    }
                })
                .disposed(by: signalDisposeBag)
            
            // 开始发送 - 确保在主线程
            DispatchQueue.main.async {
                HudHelper.instance.show(banner: .sending)
                self.transactionViewModel.send()
                
                // ✅ 修复 #4: 超时检测 + 完整清理
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    guard let self = self else { return }
                    
                    // ✅ 修复 #3: 使用锁检查（线程安全）
                    self.lock.lock()
                    let shouldTimeout = !self._finished && !self.isSending
                    if shouldTimeout {
                        self._finished = true
                    }
                    self.lock.unlock()
                    
                    if shouldTimeout {
                        print("[SendConfirm] Timeout: no response after 30s")
                        HudHelper.instance.show(banner: .error(string: "Transaction could not be sent"))
                        continuation.resume(throwing: NSError(domain: "SendError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction timeout"]))
                    }
                }
            }
        }
    }

    func openFeeSettings() -> UIViewController? {
        return EvmSendSettingsModule.viewController(settingsViewModel: settingsViewModel)
    }
}

// MARK: - SwiftUI 确认视图

struct MarketDappSendEvmConfirmationView: View {
    @ObservedObject var viewModel: MarketDappSendEvmConfirmationViewModel
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.dismiss) private var dismiss

    @State private var showFeeSettings = false

    var body: some View {
        ThemeNavigationStack {
            ThemeView(style: .list) {
                BottomGradientWrapper {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // 交易详情区域
                            transactionDetailsSection

                            // Nonce 区域（如果需要显示）
                            if viewModel.showNonce {
                                nonceSection
                            }

                            // Gas 费用区域
                            feeSection

                            // 警告信息区域
                            cautionsSection
                        }
                        .padding(.horizontal, .margin16)
                    }
                } bottomContent: {
                    VStack(spacing: .margin12) {
                        if viewModel.sendButtonState.isEnabled {
                            // 启用状态 - 显示正常的滑动按钮
                            SlideButton(
                                styling: .text(
                                    start: "send.confirmation.slide_to_send".localized,
                                    end: "",
                                    success: "✓"
                                ),
                                action: {
                                    try await viewModel.sendAsync()
                                },
                                completion: {
                                    // ✅ 关键修复：SlideButton 动画完成后的回调
                                    print("[SendConfirm] SlideButton animation completed")
                                    
                                    DispatchQueue.main.async {
                                        // 重置发送状态
                                        viewModel.isSending = false
                                        viewModel.sendError = nil
                                        
                                        // 更新按钮状态为 enabled（允许再次发送）
                                        viewModel.sendButtonState = .enabled
                                        viewModel.updateSendButtonState()
                                        
                                        // 显示成功 HUD
                                        HudHelper.instance.show(banner: .sent)
                                        
                                        // 延迟关闭确认页（让用户看到成功状态）
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                            viewModel.shouldDismiss = true
                                            
                                            // 通知父视图清除 destination（确保 DApp 页面状态正确）
                                            viewModel.onDismissed?()
                                        }
                                    }
                                }
                            )
                        } else {
                            // 禁用状态 - 显示提示和禁用按钮
                            VStack(spacing: .margin12) {
                                // 禁用原因提示
                                HStack(spacing: .margin8) {
                                    Image("warning_2_20")
                                        .renderingMode(.template)
                                        .foregroundColor(.themeJacob)
                                        .frame(width: .iconSize16, height: .iconSize16)
                                    
                                    Text(viewModel.getDisableReasonText())
                                        .font(.themeCaption)
                                        .foregroundColor(.themeJacob)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, .margin16)
                                .padding(.vertical, .margin8)
                                .background(
                                    RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous)
                                        .fill(Color.themeYellow.opacity(0.1))
                                )
                                
                                // 禁用状态的按钮
                                SlideButton(
                                    styling: .text(
                                        start: viewModel.getDisableReasonText(),
                                        end: "",
                                        success: ""
                                    ),
                                    action: {
                                        // 禁用状态下不会执行
                                    },
                                    completion: {
                                        // 禁用状态下不会执行
                                    }
                                )
                                .disabled(true)
                                .opacity(0.6)
                            }
                        }
                    }
                    .padding(.horizontal, .margin16)
                    .padding(.bottom, .margin32)
                    .padding(.top, .margin8)
                }
            }
            .navigationTitle("confirm".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showFeeSettings = true
                    }) {
                        Image("manage_2_20")
                            .renderingMode(.template)
                    }
                }
            }
            .sheet(isPresented: $showFeeSettings) {
                if let controller = viewModel.openFeeSettings() {
                    SendEvmConfirmationSheetViewController(controller: controller)
                }
            }
        }
        // 监听 shouldDismiss 状态，自动关闭确认页
        .onChange(of: viewModel.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }

    // MARK: - 交易详情区域

    private var transactionDetailsSection: some View {
        LazyVStack(spacing: .margin12) {
            ForEach(Array(viewModel.sectionViewItems.enumerated()), id: \.offset) { index, section in
                SectionView(section: section, sectionIndex: index)
            }
        }
        .padding(.top, .margin16)
    }

    // MARK: - 单个 Section 视图

    struct SectionView: View {
        let section: SendEvmTransactionViewModel.SectionViewItem
        let sectionIndex: Int

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Array(section.viewItems.enumerated()), id: \.offset) { index, item in
                    RowView(viewItem: item, isFirst: index == 0, isLast: index == section.viewItems.count - 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous)
                    .fill(Color.themeLawrence)
            )
        }
    }

    // MARK: - 行视图

    struct RowView: View {
        let viewItem: SendEvmTransactionViewModel.ViewItem
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            switch viewItem {
            case let .subhead(iconName, title, value):
                SubheadRow(iconName: iconName, title: title, value: value, isFirst: isFirst, isLast: isLast)

            case let .amount(title, token, coinAmount, currencyAmount, type):
                AmountRow(title: title, token: token, coinAmount: coinAmount, currencyAmount: currencyAmount, type: type, isFirst: isFirst, isLast: isLast)

            case let .nftAmount(iconUrl, iconPlaceholderImageName, nftAmount, type):
                NFTAmountRow(iconUrl: iconUrl, iconPlaceholderImageName: iconPlaceholderImageName, nftAmount: nftAmount, type: type, isFirst: isFirst, isLast: isLast)

            case let .doubleAmount(title, coinAmount, currencyAmount):
                DoubleAmountRow(title: title, coinAmount: coinAmount, currencyAmount: currencyAmount, isFirst: isFirst, isLast: isLast)

            case let .address(title, value, valueTitle, _, _):
                AddressRow(title: title, value: value, valueTitle: valueTitle, isFirst: isFirst, isLast: isLast)

            case let .value(title, value, type):
                ValueRow(title: title, value: value, type: type, isFirst: isFirst, isLast: isLast)

            case let .input(value):
                InputRow(value: value, isFirst: isFirst, isLast: isLast)
            }
        }
    }

    // MARK: - Subhead 行

    struct SubheadRow: View {
        let iconName: String
        let title: String
        let value: String
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: .margin16) {
                    Image(iconName)
                        .renderingMode(.template)
                        .foregroundColor(.themeGray)

                    Text(title)
                        .font(.themeSubhead2)
                        .foregroundColor(.themeLeah)

                    Spacer()

                    Text(value)
                        .font(.themeSubhead1)
                        .foregroundColor(.themeLeah)
                }
                .frame(height: .heightCell48)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }
    }

    // MARK: - 金额行

    struct AmountRow: View {
        let title: String
        let token: Token
        let coinAmount: String
        let currencyAmount: String?
        let type: AmountType
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: .margin8) {
                    Text(title)
                        .font(.themeCaption)
                        .foregroundColor(.themeGray)

                    HStack(spacing: .margin8) {
                        AsyncImage(url: URL(string: token.coin.imageUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                            default:
                                Image(token.placeholderImageName)
                                    .resizable()
                            }
                        }
                        .frame(width: .iconSize32, height: .iconSize32)
                        .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.fullBadge + " " + coinAmount)
                                .font(.themeHeadline2)
                                .foregroundColor(amountColor(type: type))

                            if let currencyAmount {
                                Text(currencyAmount)
                                    .font(.themeSubhead2)
                                    .foregroundColor(.themeGray)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(.vertical, .margin16)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }

        private func amountColor(type: AmountType) -> Color {
            switch type {
            case .neutral:
                return .themeLeah
            case .incoming:
                return .themeGreen
            case .outgoing:
                return .themeJacob
            case .secondary:
                return .themeGray
            }
        }
    }

    // MARK: - NFT 金额行

    struct NFTAmountRow: View {
        let iconUrl: String?
        let iconPlaceholderImageName: String
        let nftAmount: String
        let type: AmountType
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: .margin16) {
                    AsyncImage(url: iconUrl.flatMap { URL(string: $0) }) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                        default:
                            Image(iconPlaceholderImageName)
                                .resizable()
                        }
                    }
                    .frame(width: .iconSize32, height: .iconSize32)
                    .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8))

                    Text(nftAmount)
                        .font(.themeHeadline2)
                        .foregroundColor(amountColor(type: type))

                    Spacer()
                }
                .frame(height: .heightCell48)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }

        private func amountColor(type: AmountType) -> Color {
            switch type {
            case .neutral:
                return .themeLeah
            case .incoming:
                return .themeGreen
            case .outgoing:
                return .themeJacob
            case .secondary:
                return .themeGray
            }
        }
    }

    // MARK: - 双重金额行

    struct DoubleAmountRow: View {
        let title: String
        let coinAmount: String
        let currencyAmount: String?
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.themeCaption)
                        .foregroundColor(.themeGray)

                    Text(coinAmount)
                        .font(.themeHeadline2)
                        .foregroundColor(.themeLeah)

                    if let currencyAmount {
                        Text(currencyAmount)
                            .font(.themeSubhead2)
                            .foregroundColor(.themeGray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, .margin16)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }
    }

    // MARK: - 地址行

    struct AddressRow: View {
        let title: String
        let value: String
        let valueTitle: String?
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.themeCaption)
                        .foregroundColor(.themeGray)

                    Text(value)
                        .font(.themeSubhead1)
                        .foregroundColor(.themeLeah)
                        .lineLimit(1)

                    if let valueTitle {
                        Text(valueTitle)
                            .font(.themeSubhead2)
                            .foregroundColor(.themeGray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, .margin16)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }
    }

    // MARK: - 值行

    struct ValueRow: View {
        let title: String
        let value: String
        let type: ValueType
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.themeSubhead2)
                        .foregroundColor(.themeLeah)

                    Spacer()

                    Text(value)
                        .font(.themeSubhead1)
                        .foregroundColor(valueColor(type: type))
                }
                .frame(height: .heightCell48)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }

        private func valueColor(type: ValueType) -> Color {
            switch type {
            case .regular:
                return .themeLeah
            case .warning:
                return .themeYellow
            case .alert:
                return .themeRed
            }
        }
    }

    // MARK: - Input 数据行

    struct InputRow: View {
        let value: String
        let isFirst: Bool
        let isLast: Bool

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input")
                        .font(.themeCaption)
                        .foregroundColor(.themeGray)

                    Text(value)
                        .font(.themeSubhead1)
                        .foregroundColor(.themeLeah)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, .margin16)

                if !isLast {
                    Divider()
                        .background(Color.themeSteel)
                }
            }
        }
    }

    // MARK: - Nonce 区域

    private var nonceSection: some View {
        HStack {
            Text("send.confirmation.nonce".localized)
                .font(.themeSubhead2)
                .foregroundColor(.themeLeah)

            Spacer()

            Text(viewModel.nonceValue)
                .font(.themeSubhead1)
                .foregroundColor(.themeLeah)
        }
        .frame(height: .heightCell48)
        .background(
            RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous)
                .fill(Color.themeLawrence)
        )
    }

    // MARK: - Gas 费用区域

    private var feeSection: some View {
        Button(action: {
            showFeeSettings = true
        }) {
            HStack {
                Text("fee_settings.network_fee".localized)
                    .font(.themeSubhead2)
                    .foregroundColor(.themeLeah)

                Spacer()

                Image("edit_20")
                    .renderingMode(.template)
                    .foregroundColor(.themeGray)
            }
            .frame(height: .heightDoubleLineCell)
            .background(
                RoundedRectangle(cornerRadius: .cornerRadius12, style: .continuous)
                    .fill(Color.themeLawrence)
            )
        }
    }

    // MARK: - 警告信息区域

    private var cautionsSection: some View {
        LazyVStack(spacing: .margin12) {
            ForEach(Array(viewModel.cautions.enumerated()), id: \.offset) { index, caution in
                CautionView(caution: caution)
            }
        }
        .padding(.top, viewModel.cautions.isEmpty ? 0 : .margin12)
    }

    // MARK: - 警告项视图

    struct CautionView: View {
        let caution: TitledCaution

        var body: some View {
            HStack(alignment: .top, spacing: .margin12) {
                Image(cautionIconName)
                    .renderingMode(.template)
                    .foregroundColor(cautionColor)
                    .frame(width: .iconSize20, height: .iconSize20)

                VStack(alignment: .leading, spacing: .margin4) {
                    Text(caution.title)
                        .font(.themeSubhead2)
                        .fontWeight(.medium)
                        .foregroundColor(cautionColor)

                    Text(caution.text)
                        .font(.themeSubhead2)
                        .foregroundColor(.themeLeah)
                }

                Spacer()
            }
            .padding(.margin16)
            .background(cautionBackgroundColor(type: caution.type).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: .cornerRadius8, style: .continuous))
        }

        private var cautionIconName: String {
            switch caution.type {
            case .error:
                return "warning_2_20"
            case .warning:
                return "warning_2_20"
            }
        }

        private var cautionColor: Color {
            switch caution.type {
            case .error:
                return .themeLucian
            case .warning:
                return .themeJacob
            }
        }

        private func cautionBackgroundColor(type: CautionType) -> Color {
            switch type {
            case .error:
                return .themeRed
            case .warning:
                return .themeYellow
            }
        }
    }
}

// MARK: - UIKit Sheet 包装器（用于展示 Fee 设置）

struct SendEvmConfirmationSheetViewController: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
