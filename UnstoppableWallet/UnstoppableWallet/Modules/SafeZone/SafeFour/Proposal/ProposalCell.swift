import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class ProposalCell: UITableViewCell {
    private let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let cardView = CardView(insets: .zero)
    private let idLabel = UILabel()
    private let stateView = BadgeView()
    private let safeAmountLabel = UILabel()
    private let addressLabel = UILabel()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    
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
        
        safeAmountLabel.font = .subhead2
        safeAmountLabel.textColor = .themeGray
        cardView.addSubview(safeAmountLabel)
        safeAmountLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
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
        
        timeLabel.textColor = .themeGray
        timeLabel.textAlignment = .right
        timeLabel.font = .subhead1
        cardView.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(CGFloat.margin8)
        }
        
        idLabel.font = .subhead2
        idLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cardView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.trailing.equalTo(timeLabel.snp.leading).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
        }
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    func bind(viewItem: ProposalViewModel.ViewItem) {
        titleLabel.text = viewItem.info.title
        safeAmountLabel.text =  "safe_zone.safe4.apply.quantity".localized + ": " + viewItem.amount + " SAFE"
        addressLabel.text =  "safe_zone.safe4.creater".localized + ": " + truncatedText(viewItem.info.creator.address, maxLength: 20)
        idLabel.text = "safe_zone.row.proposal".localized + "ID: " + "\(viewItem.info.id.description)"
        timeLabel.text = viewItem.dateText
        stateView.text = viewItem.status.title
        stateView.backgroundColor = viewItem.status.color
    }
    
    private func truncatedText(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        
        let start = text.prefix(maxLength / 2)
        let end = text.suffix(maxLength / 2)
        
        return "\(start)...\(end)"
    }
    
    static func height() -> CGFloat {
        return 120
    }
}

