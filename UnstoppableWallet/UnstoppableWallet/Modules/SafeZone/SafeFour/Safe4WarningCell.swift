import UIKit
import ThemeKit
import SnapKit
import RxSwift
import ComponentKit

class Safe4WarningCell: UITableViewCell {
    private static let margins = UIEdgeInsets(top: 1, left: CGFloat.margin16, bottom: 1, right: CGFloat.margin16)
    private static let horizontalPadding: CGFloat = .margin16
    private static let verticalPadding: CGFloat = .margin12
    private static let imagPadding: CGFloat = .margin12
    private static let font: UIFont = .subhead2
    
    let bgView = UIView()
    let borderView = UIView()
    let imgView = UIImageView()
    let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none
        
        bgView.backgroundColor = .white
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Self.margins)
        }
        
        borderView.cornerRadius = 4
        contentView.addSubview(borderView)
        borderView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Self.margins)
        }
        borderView.borderWidth = 1
        contentView.addSubview(borderView)
        borderView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Self.margins)
        }
        
        borderView.addSubview(imgView)
        imgView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalPadding)
            make.top.equalToSuperview().offset(Self.verticalPadding)
            make.size.equalTo(CGSize(width: 24, height: 24))
        }
        
        borderView.addSubview(label)
        label.snp.makeConstraints { make in
            make.top.equalTo(imgView)
            make.leading.equalTo(imgView.snp.trailing).offset(Self.verticalPadding)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.bottom.equalToSuperview().inset(Self.verticalPadding)
        }

        label.numberOfLines = 0
        label.font = Safe4WarningCell.font
        label.textColor = .themeBran
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(text: String, type: WarningType) {
        label.text = text
        borderView.borderColor = type.borderColor
        borderView.backgroundColor = type.backgroundColor
        imgView.image = UIImage(named: "circle_information_20")?.withTintColor(type.imageColor)
    }
}

extension Safe4WarningCell {
    
    func height(containerWidth: CGFloat, font: UIFont? = nil, ignoreBottomMargin: Bool = false) -> CGFloat {
        var textHeight: CGFloat = 0
        if let str = label.text, str.contains("\n") {
            let splitResult = str.split(separator: "\n").map { String($0) }
            textHeight = splitResult.map{$0.height(forContainerWidth: containerWidth - 100, font: font ?? Self.font)}.reduce(0, +)

        } else {
            let text = label.text ?? "-"
            textHeight = text.height(forContainerWidth: containerWidth - 100, font: font ?? Self.font)
        }
        return textHeight + (ignoreBottomMargin ? 1 : 2) * Self.verticalPadding + Self.margins.top + Self.margins.bottom
    }
}
extension Safe4WarningCell {
    enum WarningType {
        case normal
        case warning
        
        var imageColor: UIColor {
            switch self {
            case .normal: return .themeIssykBlue
            case .warning: return .themeYellowL
            
            }
        }
        
        var borderColor: UIColor {
            switch self {
            case .normal: return .themeIssykBlue.withAlphaComponent(0.5)
            case .warning: return .themeYellowL.withAlphaComponent(0.5)
            
            }
        }
        
        var backgroundColor: UIColor {
            switch self {
            case .normal: return .themeIssykBlue.withAlphaComponent(0.2)
            case .warning: return .themeYellowL.withAlphaComponent(0.2)
            
            }
        }
    }
}
