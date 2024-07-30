import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit

class NodeDetailVoteRecordHeaderView: UITableViewHeaderFooterView {
    private let titleLabel = UILabel()
    private let idLabel = UILabel()
    private let addressLabel = UILabel()
    private let amountLabel = UILabel()
    
    init(hasTopSeparator: Bool = true) {

        super.init(reuseIdentifier: nil)

        backgroundView = UIView()
        backgroundView?.backgroundColor = .themeNavigationBarBackground

        if hasTopSeparator {
            let separatorView = UIView()
            contentView.addSubview(separatorView)
            separatorView.snp.makeConstraints { maker in
                maker.leading.trailing.equalToSuperview()
                maker.top.equalToSuperview()
                maker.height.equalTo(CGFloat.heightOnePixel)
            }

            separatorView.backgroundColor = .themeSteel20
        }
        
        titleLabel.text = "创建人 | 合伙人".localized
        titleLabel.font = .headline2
        titleLabel.textColor = .themeIssykBlue
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin4)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        idLabel.text = "safe_zone.safe4.vote.record.id".localized
        idLabel.numberOfLines = 0
        idLabel.font = .subhead2
        contentView.addSubview(idLabel)
        idLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.width.equalTo(CGFloat.margin48)
        }
        
        addressLabel.text = "safe_zone.safe4.vote.record.address".localized
        addressLabel.font = .subhead2
        contentView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalTo(idLabel.snp.trailing).offset(CGFloat.margin6)
        }
        
        amountLabel.text = "safe_zone.safe4.vote.record.amount".localized
        amountLabel.font = .subhead2
        amountLabel.textAlignment = .right
        amountLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contentView.addSubview(amountLabel)
        amountLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalTo(addressLabel.snp.trailing).offset(CGFloat.margin6)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
    }
    
    static func height() -> CGFloat {
        return .heightDoubleLineCell
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
