import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class SuperNodeCell: UITableViewCell {
    private let cardView = CardView(insets: .zero)
    private let topView = UIView()
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
    private let typeView = BadgeView()

    private let joinButton = UIButton(type: .custom)
    private let editButton = UIButton(type: .custom)
    private let voteButton = UIButton(type: .custom)
    private let addLockButton = UIButton(type: .custom)

    private let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    
    var toDetail: (() -> Void)?
    var toJoin: (() -> Void)?
    var toEdit: (() -> Void)?
    var toVote: (() -> Void)?
    var toAddLock: (() -> Void)?
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(margins)
        }
        
        topView.backgroundColor = .clear
        topView.isUserInteractionEnabled = true
        let toDetailRecognizer = UITapGestureRecognizer(target: self, action: #selector(detail))
        topView.addGestureRecognizer(toDetailRecognizer)
        cardView.addSubview(topView)
        topView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        
        rankingLabel.font = .subhead2
        rankingLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        topView.addSubview(rankingLabel)
        rankingLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(CGFloat.margin8)
        }

        idLabel.font = .subhead2
        cardView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.top.equalTo(rankingLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
        }
        
        stateView.set(style: .medium)
        stateView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        topView.addSubview(stateView)
        stateView.snp.makeConstraints { make in
            make.centerY.equalTo(idLabel)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalTo(idLabel.snp.trailing).offset(CGFloat.margin8)
        }
        
        titleLabel.font = .subhead2
        topView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(idLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
        
        addressLabel.font = .subhead2
        topView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
        }
        
        typeView.isHidden = true
        typeView.set(style: .medium)
        typeView.backgroundColor = .themeIssykBlue
        typeView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        topView.addSubview(typeView)
        typeView.snp.makeConstraints { make in
            make.centerY.equalTo(addressLabel)
            make.leading.equalTo(addressLabel.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin12)
        }
        
        votesLabel.font = .subhead2
        topView.addSubview(votesLabel)
        votesLabel.snp.makeConstraints { make in
            make.top.equalTo(addressLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().inset(CGFloat.margin8)
        }
        
        safeAmountLabel.font = .subhead2
        topView.addSubview(safeAmountLabel)
        safeAmountLabel.snp.makeConstraints { make in
            make.top.equalTo(addressLabel.snp.bottom).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin12)
        }
        
        ratioLabel.font = .subhead1
        topView.addSubview(ratioLabel)

        slider.setThumbImage(UIImage(), for: .normal)
        slider.isUserInteractionEnabled = false
        topView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.centerY.equalTo(ratioLabel)
        }
        
        ratioLabel.snp.makeConstraints { make in
            make.top.equalTo(safeAmountLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalTo(slider.snp.trailing).offset(CGFloat.margin12)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }

        joinButton.setTitle("safe_zone.safe4.node.join.partner".localized, for: .normal)
        joinButton.setTitleColor(.themeLeah, for: .normal)
        joinButton.setTitleColor(.themeGray, for: .disabled)
        joinButton.addTarget(self, action: #selector(join), for: .touchUpInside)
        joinButton.setBackgroundColor(.themeYellowD, for: .normal)
        joinButton.setBackgroundColor(.themeDisabledBgGray, for: .disabled)
        joinButton.cornerRadius = .cornerRadius12
        joinButton.titleLabel?.font = .subhead1
        joinButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        cardView.addSubview(joinButton)
        joinButton.snp.makeConstraints { make in
            make.top.equalTo(topView.snp.bottom).offset(CGFloat.margin8)
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.height.equalTo(.heightButton/2)
        }
        
        voteButton.setTitle("投票".localized, for: .normal)
        voteButton.setTitleColor(.themeLeah, for: .normal)
        voteButton.setTitleColor(.themeGray, for: .disabled)
        voteButton.addTarget(self, action: #selector(vote), for: .touchUpInside)
        voteButton.setBackgroundColor(.themeYellowD, for: .normal)
        voteButton.setBackgroundColor(.themeDisabledBgGray, for: .disabled)
        voteButton.cornerRadius = .cornerRadius12
        voteButton.titleLabel?.font = .subhead1
        voteButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        cardView.addSubview(voteButton)
        voteButton.snp.makeConstraints { make in
            make.centerY.height.equalTo(joinButton)
            make.leading.equalTo(joinButton.snp.trailing).offset(CGFloat.margin8)
        }
        
        editButton.setTitle("safe_zone.safe4.node.edit".localized, for: .normal)
        editButton.setTitleColor(.themeLeah, for: .normal)
        editButton.setTitleColor(.themeGray, for: .disabled)
        editButton.addTarget(self, action: #selector(edit), for: .touchUpInside)
        editButton.setBackgroundColor(.themeYellowD, for: .normal)
        editButton.setBackgroundColor(.themeDisabledBgGray, for: .disabled)
        editButton.cornerRadius = .cornerRadius12
        editButton.titleLabel?.font = .subhead1
        editButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        cardView.addSubview(editButton)
        editButton.snp.makeConstraints { make in
            make.centerY.height.equalTo(joinButton)
            make.width.equalTo(voteButton)
            make.leading.equalTo(voteButton.snp.trailing).offset(CGFloat.margin8)
        }
        
        addLockButton.setTitle("safe_zone.safe4.node.locked.days.add.title".localized, for: .normal)
        addLockButton.setTitleColor(.themeLeah, for: .normal)
        addLockButton.setTitleColor(.themeGray, for: .disabled)
        addLockButton.addTarget(self, action: #selector(addLock), for: .touchUpInside)
        addLockButton.setBackgroundColor(.themeYellowD, for: .normal)
        addLockButton.setBackgroundColor(.themeDisabledBgGray, for: .disabled)
        addLockButton.cornerRadius = .cornerRadius12
        addLockButton.titleLabel?.font = .subhead1
        addLockButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        cardView.addSubview(addLockButton)
        addLockButton.snp.makeConstraints { make in
            make.centerY.height.equalTo(joinButton)
            make.width.equalTo(editButton)
            make.leading.equalTo(editButton.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }

    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    func bind(viewItem: SuperNodeViewModel.ViewItem, index: Int) {
        rankingLabel.isHidden = viewItem.isEnabledEdit
        rankingLabel.text = "safe_zone.safe4.ranking".localized + "\(index)"

        titleLabel.text = "节点名称:".localized + viewItem.info.name
        votesLabel.text = "投票数:".localized + viewItem.totalVoteNum.safe4FomattedAmount
        safeAmountLabel.text = "质押数:".localized + "\(viewItem.totalAmount.safe4FomattedAmount) SAFE"

        let attributedString: NSAttributedString = NSMutableAttributedString(string: "safe_zone.safe4.node.address".localized + truncatedText(viewItem.info.addr.address, maxLength: 20), attributes: [
            .foregroundColor: viewItem.ownerType != .None ? UIColor.themeIssykBlue : UIColor.themeLeah,
            .font: UIFont.subhead2,
        ])
        addressLabel.attributedText = attributedString
        idLabel.text = "safe_zone.safe4.node".localized + "ID: " + "\(viewItem.info.id.description)"
        stateView.text = viewItem.nodeState.title
        stateView.backgroundColor = viewItem.nodeState.color
        joinButton.isEnabled = viewItem.isEnabledJoin
        ratioLabel.text = (viewItem.rate * 100).safe4FormattedAmount + "%"
        slider.value = (viewItem.rate as NSDecimalNumber).floatValue
        editButton.isEnabled = viewItem.isEnabledEdit && viewItem.ownerType == .Creator
        voteButton.isEnabled = viewItem.isEnabledVote
        addLockButton.isEnabled = viewItem.isEnabledAddLockDay
        typeView.isHidden = viewItem.ownerType == .None || viewItem.ownerType == .Owner
        typeView.text = viewItem.ownerType.title
    }
    
    var joinEnabled: Bool {
        joinButton.isSelected
    }
    
    private func truncatedText(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let start = text.prefix(maxLength / 2)
        let end = text.suffix(maxLength / 2)
        return "\(start)...\(end)"
    }
    
    static func height() -> CGFloat {
        return 200
    }
    
    @objc private func detail() {
        toDetail?()
    }
    @objc private func join() {
        toJoin?()
    }
    
    @objc private func edit() {
        toEdit?()
    }
    
    @objc private func vote() {
        toVote?()
    }
    
    @objc private func addLock() {
        toAddLock?()
    }
}
