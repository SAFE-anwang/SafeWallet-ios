import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class SuperNodeCell: UITableViewCell {
    private static let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let cardView = CardView(insets: .zero)
    private let rankLabel = UILabel()
    private let stateView = BadgeView()
    
    private let titleLabel = UILabel()
    private let subTitleLabel = UILabel()
    
    private let votesLabel = UILabel()
    private let safeAmountLabel = UILabel()
    private let ratioLabel = UILabel()
    private let slider = UISlider()
    
    private let addressLabel = UILabel()
    private let idLabel = UILabel()
    private let rankingLabel = UILabel()
    private let joinView = BadgeView()    
    
    private let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(margins)
        }
    
        titleLabel.font = .headline2
        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(CGFloat.margin8)
        }

        stateView.set(style: .medium)
        stateView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardView.addSubview(stateView)
        stateView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalTo(titleLabel.snp.trailing).offset(CGFloat.margin8)
        }
        
        rankingLabel.font = .subhead2
        rankingLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardView.addSubview(rankingLabel)
        rankingLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
        }
        
        idLabel.font = .subhead2
        cardView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalTo(rankingLabel.snp.trailing).offset(CGFloat.margin16)
        }
        
        joinView.set(style: .medium)
        joinView.backgroundColor = .themeIssykBlue
        joinView.text = "safe_zone.safe4.node.join.partner".localized
        joinView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardView.addSubview(joinView)
        joinView.snp.makeConstraints { make in
            make.centerY.equalTo(idLabel)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
        addressLabel.font = .subhead1
        addressLabel.textColor = .themeGray
        cardView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.top.equalTo(idLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
        ratioLabel.font = .subhead1
        cardView.addSubview(ratioLabel)
        
        slider.setThumbImage(UIImage(), for: .normal)
        slider.isUserInteractionEnabled = false
        cardView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.centerY.equalTo(ratioLabel)
        }

        ratioLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalTo(slider.snp.trailing).offset(CGFloat.margin12)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
        votesLabel.font = .subhead2
        cardView.addSubview(votesLabel)
        votesLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin32)
            make.leading.equalToSuperview().inset(CGFloat.margin8)
        }
        
        safeAmountLabel.font = .subhead2
        safeAmountLabel.textColor = .themeGray
        cardView.addSubview(safeAmountLabel)
        safeAmountLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin32)
            make.trailing.equalToSuperview().inset(CGFloat.margin12)
        }
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    func bind(viewItem: SuperNodeViewModel.ViewItem, index: Int) {
        rankingLabel.text = "排名: " + "\(index)"
        titleLabel.text = viewItem.info.name
        votesLabel.text = viewItem.totalVoteNum.safe4FomattedAmount
        safeAmountLabel.text = "[\(viewItem.totalAmount.safe4FomattedAmount)  SAFE]"
        addressLabel.text = "safe_zone.safe4.node.address".localized + ": " + truncatedText(viewItem.info.creator.address, maxLength: 20)
        idLabel.text = "safe_zone.safe4.node".localized + "ID: " + "\(viewItem.info.id.description)"
        stateView.text = viewItem.nodeState.title
        stateView.backgroundColor = viewItem.nodeState.color
        joinView.isHidden = !viewItem.joinEnabled
        ratioLabel.text = (viewItem.rate * 100).safe4FormattedAmount + "%"
        slider.value = (viewItem.rate as NSDecimalNumber).floatValue
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
        return 140
    }
}
