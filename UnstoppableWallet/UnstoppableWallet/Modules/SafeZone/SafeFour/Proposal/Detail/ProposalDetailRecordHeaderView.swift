import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
class ProposalDetailRecordHeaderView: UITableViewHeaderFooterView {
    private let titleLabel = UILabel()
    private let addressLabel = UILabel()
    private let voteResultLabel = UILabel()
    
    init(hasTopSeparator: Bool = true) {

        super.init(reuseIdentifier: nil)
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
        
        titleLabel.text = "safe_zone.safe4.proposal.detail.info.vote.record".localized
        titleLabel.font = .headline2
//        titleLabel.textColor = .themeIssykBlue
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin4)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        addressLabel.text = "safe_zone.safe4.node.super.title".localized
        addressLabel.font = .subhead1
        contentView.addSubview(addressLabel)
        addressLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
        }
        
        voteResultLabel.text = "safe_zone.safe4.vote.results".localized
        voteResultLabel.font = .subhead1
        voteResultLabel.textAlignment = .right
        contentView.addSubview(voteResultLabel)
        voteResultLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin8)
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
