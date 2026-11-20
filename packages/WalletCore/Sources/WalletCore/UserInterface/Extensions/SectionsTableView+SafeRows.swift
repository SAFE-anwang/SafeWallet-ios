import SectionsTableView
import UIKit

extension SectionsTableView {
    func multilineRow(id: String, title: String, value: String, backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence, layoutMargins: UIEdgeInsets? = nil, autoDeselect: Bool = false, isFirst: Bool = false, isLast: Bool = false, isLineThrough: Bool = false,  isShowCheckbox: Bool = false, isChoosed: Bool = false, subTextColor: UIColor = .label, action: (() -> Void)? = nil) -> RowProtocol {
        let layout: UIEdgeInsets = layoutMargins ?? UIEdgeInsets(top: .margin8, left: .margin16, bottom: .margin12, right: .margin16)
        let titleFont: UIFont = .subhead2
        let valueFont: UIFont = .subhead1

        return CellBuilderNew.row(
            rootElement: .hStack([
                .vStack([
                    .text { (component: TextComponent) -> () in
                        component.setContentHuggingPriority(.required, for: .vertical)
                        component.font = titleFont
                        component.textColor = .themeGray
                        component.text = title
                    },
                    .margin4,
                    .text { (component: TextComponent) -> () in
                        component.font = valueFont
                        component.numberOfLines = 0

                        if isLineThrough {
                            let attributeString: NSMutableAttributedString = NSMutableAttributedString(string: value)
                            attributeString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
                            attributeString.addAttribute(.foregroundColor, value: subTextColor, range: NSRange(location: 0, length: attributeString.length))
                            component.attributedText = attributeString
                        }else {
                            component.attributedText = nil
                            component.textColor = subTextColor
                            component.text = value
                        }
                    },
                ]),
                .imageElement(image: isShowCheckbox ? (isChoosed ? .local(UIImage(named: "checkbox_active_24")) : .local(UIImage(named: "checkbox_diactive_24"))): nil, size:  .image24),
            ]),
            layoutMargins: layout,
            tableView: self,
            id: id,
            hash: value,
            autoDeselect: autoDeselect,
            dynamicHeight: { containerWidth in
                return CellBuilderNew.height(
                    containerWidth: containerWidth,
                    backgroundStyle: backgroundStyle,
                    text: value,
                    font: valueFont,
                    elements: [
                        .margin16,
                        .margin16,
                        .multiline,
                        .margin24
                    ]
                ) + 10
            },
            bind: { cell in
                cell.selectionStyle = .none
                cell.set(backgroundStyle: backgroundStyle, isFirst: isFirst, isLast: isLast)
            },
            action: action
        )
    }
}

extension SectionsTableView {
    func messageRow(text: String) -> RowProtocol {
        let backgroundStyle: BaseThemeCell.BackgroundStyle = .lawrence
        let font: UIFont = .caption

        return CellBuilderNew.row(
            rootElement: .hStack([
                .text { component in
                    component.font = font
                    component.textColor = .themeLeah
                    component.text = text
                    component.numberOfLines = 0
                },
            ]),
            tableView: self,
            id: "message",
            hash: text,
            autoDeselect: true,
            dynamicHeight: { containerWidth in
                CellBuilderNew.height(
                    containerWidth: containerWidth,
                    backgroundStyle: backgroundStyle,
                    text: text,
                    font: font,
                    elements: [.multiline]
                )
            },
            bind: { cell in
                cell.set(backgroundStyle: .lawrence, isFirst: true, isLast: true)
            },
            action: {
                CopyHelper.copyAndNotify(value: text)
            }
        )
    }
}
