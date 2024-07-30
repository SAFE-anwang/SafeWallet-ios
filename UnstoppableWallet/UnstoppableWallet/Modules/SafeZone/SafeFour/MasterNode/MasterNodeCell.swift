import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class MasterNodeCell: UITableViewCell {
    private let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let cardView = CardView(insets: .zero)
    private let idLabel = UILabel()
    private let stateView = BadgeView()
    private let safeAmountLabel = UILabel()
    private let addressLabel = UILabel()
    private let joinView = BadgeView()
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(margins)
        }
        
        idLabel.font = .headline2
        cardView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(CGFloat.margin8)
        }

        stateView.set(style: .medium)
        stateView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardView.addSubview(stateView)
        stateView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalTo(idLabel.snp.trailing).offset(CGFloat.margin8)
        }
        
        safeAmountLabel.font = .subhead2
        safeAmountLabel.textColor = .themeGray
        cardView.addSubview(safeAmountLabel)
        safeAmountLabel.snp.makeConstraints { make in
            make.top.equalTo(idLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
        joinView.isHidden = true
        joinView.set(style: .medium)
        joinView.backgroundColor = .themeIssykBlue
        joinView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardView.addSubview(joinView)
        joinView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
        addressLabel.font = .subhead1
        addressLabel.textColor = .themeGray
        addressLabel.lineBreakMode = .byTruncatingMiddle
        cardView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.top.equalTo(safeAmountLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    func bind(viewItem: MasterNodeViewModel.ViewItem) {
        safeAmountLabel.text = "safe_zone.safe4.node.pledge".localized + "SAFE: " + viewItem.amount + " SAFE"
        addressLabel.text = "safe_zone.safe4.node.address".localized + ": " + truncatedText(viewItem.info.creator.address, maxLength: 20)
        idLabel.text = "safe_zone.safe4.node".localized + "ID: " + "\(viewItem.info.id.description)"
        stateView.text = viewItem.nodeState.title
        stateView.backgroundColor = viewItem.nodeState.color
        joinView.text = "safe_zone.safe4.node.join.partner".localized
        joinView.isHidden = !viewItem.joinEnabled
    }
    
    var joinEnabled: Bool {
        !joinView.isHidden
    }
    
    private func truncatedText(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let start = text.prefix(maxLength / 2)
        let end = text.suffix(maxLength / 2)
        return "\(start)...\(end)"
    }
    
    static func height() -> CGFloat {
        return 100
    }
}
