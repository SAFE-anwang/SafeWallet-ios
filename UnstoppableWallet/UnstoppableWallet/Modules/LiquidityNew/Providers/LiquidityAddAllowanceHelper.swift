import EvmKit
import Foundation
import MarketKit
import SwiftUI

class LiquidityAddAllowanceHelper {
    private let adapterManager = Core.shared.adapterManager
    private let addressesForRevoke: [BlockchainType: String] = [
        .ethereum: "0xdac17f958d2ee523a2206206994597c13d831ec7",
        .tron: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
    ]

    func preSwapView(step: MultiSwapPreSwapStep, token: Token, amount: Decimal, isPresented: Binding<Bool>, onSuccess: @escaping () -> Void) -> AnyView {
        switch step {
        case let unlockStep as UnlockStep:
            if unlockStep.isRevoke {
                let view = MultiSwapRevokeView(tokenIn: token, spenderAddress: unlockStep.spenderAddress, isPresented: isPresented, onSuccess: onSuccess)
                return AnyView(ThemeNavigationStack { view })
            } else {
                let view = MultiSwapApproveView(tokenIn: token, amount: amount, spenderAddress: unlockStep.spenderAddress, isPresented: isPresented, onSuccess: onSuccess)
                return AnyView(ThemeNavigationStack { view })
            }
        default:
            return AnyView(Text("Invalid Pre Swap Step"))
        }
    }

    func allowanceState(spenderAddress: Address, token: Token, amount: Decimal) async -> AllowanceState {
        if token.type.isNative {
            return .notRequired
        }

        guard let adapter = adapterManager.adapter(for: token) as? IAllowanceAdapter else {
            return .unknown
        }

        do {
            // 首先获取链上最新的授权额度
            let allowance = try await adapter.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)
            
            // 如果授权额度已满足要求，直接返回.allowed
            if amount <= allowance {
                return .allowed
            }
            
            // 检查是否有待处理的授权交易
            let pendingAllowance = pendingAllowance(pendingTransactions: adapter.pendingTransactions, spenderAddress: spenderAddress)
            
            if let pendingAllowance {
                // 如果有pending授权交易，且pending的授权额度满足要求
                if pendingAllowance == 0 {
                    // pending的是撤销授权
                    return allowance == 0 ? .notEnough(appValue: AppValue(token: token, value: allowance), spenderAddress: spenderAddress, revokeRequired: false) : .pendingRevoke
                } else {
                    // pending的是授权交易
                    // 检查pending的授权额度是否满足要求
                    if amount <= pendingAllowance {
                        // Safe 链特殊处理：如果 pending 的授权金额足够，直接返回 allowed
                        // 这样在区块高度变化后，用户就可以立即执行添加流动性
                        if token.blockchainType == .safe4 {
                            return .allowed
                        }
                        return .pendingAllowance(appValue: AppValue(token: token, value: pendingAllowance))
                    } else {
                        // pending的授权额度仍不满足要求，显示为notEnough
                        return .notEnough(
                            appValue: AppValue(token: token, value: allowance),
                            spenderAddress: spenderAddress,
                            revokeRequired: allowance > 0 && mustBeRevoked(token: token)
                        )
                    }
                }
            }

            return .notEnough(
                appValue: AppValue(token: token, value: allowance),
                spenderAddress: spenderAddress,
                revokeRequired: allowance > 0 && mustBeRevoked(token: token)
            )
        } catch {
            return .notEnough(
                appValue: AppValue(token: token, value: 0),
                spenderAddress: spenderAddress,
                revokeRequired: false
            )
        }
    }

    private func pendingAllowance(pendingTransactions: [TransactionRecord], spenderAddress: Address) -> Decimal? {
        for transaction in pendingTransactions {
            if let record = transaction as? IApproveTransaction, record.spender.lowercased() == spenderAddress.raw.lowercased() {
                return record.value.value
            }
        }

        return nil
    }

    private func mustBeRevoked(token: Token) -> Bool {
        for (blockchainType, addressToRevoke) in addressesForRevoke {
            if blockchainType == token.blockchainType, case let .eip20(address) = token.type, address.lowercased() == addressToRevoke.lowercased() {
                return true
            }
        }

        return false
    }
}

extension LiquidityAddAllowanceHelper {
    enum AllowanceState {
        case notRequired
        case pendingAllowance(appValue: AppValue)
        case pendingRevoke
        case notEnough(appValue: AppValue, spenderAddress: Address, revokeRequired: Bool)
        case allowed
        case unknown

        var customButtonState: MultiSwapButtonState? {
            switch self {
            case let .notEnough(_, spenderAddress, revokeRequired): return .init(title: revokeRequired ? "swap.revoke".localized : "swap.approve".localized, preSwapStep: UnlockStep(spenderAddress: spenderAddress, isRevoke: revokeRequired))
            case .pendingAllowance: return .init(title: "swap.approving".localized, disabled: true, showProgress: true)
            case .pendingRevoke: return .init(title: "swap.revoking".localized, disabled: true, showProgress: true)
            case .unknown: return .init(title: "swap.allowance_error".localized, disabled: true)
            default: return nil
            }
        }

        func cautions() -> [CautionNew] {
            var cautions = [CautionNew]()

            switch self {
            case let .notEnough(appValue, _, revokeRequired):
                if revokeRequired {
                    cautions.append(.init(text: "swap.revoke_warning".localized(appValue.formattedShort() ?? ""), type: .warning))
                }
            default: ()
            }

            return cautions
        }
    }

    class UnlockStep: MultiSwapPreSwapStep {
        let spenderAddress: Address
        let isRevoke: Bool

        init(spenderAddress: Address, isRevoke: Bool) {
            self.spenderAddress = spenderAddress
            self.isRevoke = isRevoke
        }

        override var id: String {
            "eip20_unlock"
        }
    }
}
