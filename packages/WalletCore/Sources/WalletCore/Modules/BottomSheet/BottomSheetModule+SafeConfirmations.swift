import UIKit

extension BottomSheetModule {
    static func fallbackBlockConfirmation(action: (() -> ())?) -> UIViewController {
        viewController(
            image: .warning,
                title: "safe_setting.fallback.sheet.title".localized,
                items: [
                    .highlightedDescription(text: "safe_setting.fallback.sheet.desc".localized)
                ],
                buttons: [
                    .init(style: .yellow, title: "safe_setting.fallback.sheet.button".localized) {
                        action?()
                    },
                    .init(style: .transparent, title: "button.cancel".localized)
                ]
        )
    }

    static func removeLiquidityConfirmation(action: (() -> ())?) -> UIViewController {
        viewController(
                image: .warning,
                title: "liquidity.remove".localized,
                items: [
                    .highlightedDescription(text: "liquidity.remove.description".localized)
                ],
                buttons: [
                    .init(style: .yellow, title: "button.ok".localized) {
                        action?()
                    },
                    .init(style: .transparent, title: "button.cancel".localized)
                ]
        )
    }

    static func addLockDaysConfirmation(days: String, action: (() -> ())?) -> UIViewController {
        viewController(
            image: .warning,
                title: "safe_zone.safe4.node.locked.days.add.title".localized,
                items: [
                    .highlightedDescription(text:  "safe_zone.safe4.node.locked.days.add.title".localized + ": \(days)" + "safe_zone.safe4.node.locked.days.title".localized.localized)
                ],
                buttons: [
                    .init(style: .yellow, title: "button.ok".localized) {
                        action?()
                    },
                    .init(style: .transparent, title: "button.cancel".localized)
                ]
        )
    }

    static func withdrawConfirmation(action: (() -> ())?) -> UIViewController {
        viewController(
            image: .warning,
            title: "safe_zone.safe4.withdraw".localized,
                items: [
                    .description(text: "safe_zone.withdraw_no_more_yield".localized)
                ],
                buttons: [
                    .init(style: .yellow, title: "button.ok".localized) {
                        action?()
                    },
                    .init(style: .transparent, title: "button.cancel".localized)
                ]
        )
    }
}
