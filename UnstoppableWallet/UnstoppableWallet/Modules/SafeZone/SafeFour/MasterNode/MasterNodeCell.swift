import UIKit
import ThemeKit
import SnapKit
import ComponentKit
import BigInt

class MasterNodeCell: UITableViewCell {
    private let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let cardView = CardView(insets: .zero)
    private let topView = UIView()
    private let idLabel = UILabel()
    private let stateView = BadgeView()
    private let votesLabel = UILabel()
    private let safeAmountLabel = UILabel()
    private let addressLabel = UILabel()
    private let typeView = BadgeView()
    private let joinButton = UIButton(type: .custom)
    private let editButton = UIButton(type: .custom)
    private let addLockButton = UIButton(type: .custom)

    var toDetail: (() -> Void)?
    var toJoin: (() -> Void)?
    var toEdit: (() -> Void)?
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
        
        idLabel.font = .headline2
        topView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(CGFloat.margin12)
        }

        stateView.set(style: .medium)
        stateView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        topView.addSubview(stateView)
        stateView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalTo(idLabel.snp.trailing).offset(CGFloat.margin8)
        }
        
        addressLabel.font = .subhead2
        topView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.top.equalTo(idLabel.snp.bottom).offset(CGFloat.margin8)
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
        safeAmountLabel.textColor = .themeGray
        cardView.addSubview(votesLabel)
        votesLabel.snp.makeConstraints { make in
            make.top.equalTo(addressLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)

        }

        safeAmountLabel.font = .subhead2
        safeAmountLabel.textColor = .themeGray
        cardView.addSubview(safeAmountLabel)
        safeAmountLabel.snp.makeConstraints { make in
            make.top.equalTo(addressLabel.snp.bottom).offset(CGFloat.margin8)
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
        joinButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        cardView.addSubview(joinButton)
        joinButton.snp.makeConstraints { make in
            make.top.equalTo(topView.snp.bottom).offset(CGFloat.margin8)
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.height.equalTo(.heightButton/2)
        }
        
        editButton.setTitle("safe_zone.safe4.node.edit".localized, for: .normal)
        editButton.setTitleColor(.themeLeah, for: .normal)
        editButton.setTitleColor(.themeGray, for: .disabled)
        editButton.addTarget(self, action: #selector(edit), for: .touchUpInside)
        editButton.setBackgroundColor(.themeYellowD, for: .normal)
        editButton.setBackgroundColor(.themeDisabledBgGray, for: .disabled)
        editButton.cornerRadius = .cornerRadius12
        editButton.titleLabel?.font = .subhead1
        editButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        cardView.addSubview(editButton)
        editButton.snp.makeConstraints { make in
            make.centerY.height.equalTo(joinButton)
            make.width.equalTo(joinButton)
            make.leading.equalTo(joinButton.snp.trailing).offset(CGFloat.margin8)
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
    
    func bind(viewItem: MasterNodeViewModel.ViewItem) {
        votesLabel.text = "投票数:".localized + viewItem.amount
        safeAmountLabel.text = "质押数:".localized + "\(viewItem.amount) SAFE"
        let attributedString: NSAttributedString = NSMutableAttributedString(string: "safe_zone.safe4.node.address".localized + truncatedText(viewItem.info.addr.address, maxLength: 20), attributes: [
            .foregroundColor: viewItem.ownerType != .None ? UIColor.themeIssykBlue : UIColor.themeGray,//UIColor.themeGray,
            .font: UIFont.subhead1,
        ])
        addressLabel.attributedText = attributedString
        idLabel.text = "safe_zone.safe4.node".localized + "ID: " + "\(viewItem.info.id.description)"
        stateView.text = viewItem.nodeState.title
        stateView.backgroundColor = viewItem.nodeState.color
        joinButton.isEnabled = viewItem.isEnabledJoin
        editButton.isEnabled = viewItem.isEnabledEdit && viewItem.ownerType == .Creator
        addLockButton.isEnabled = viewItem.ownerType == .Partner || viewItem.ownerType == .Creator
        typeView.isHidden = viewItem.ownerType == .None
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
        return 135
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
    
    @objc private func addLock() {
        toAddLock?()
    }
}
