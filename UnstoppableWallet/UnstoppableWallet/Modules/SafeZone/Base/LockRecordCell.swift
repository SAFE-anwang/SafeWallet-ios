import RxCocoa
import RxSwift
import SnapKit
import UIKit
import UIExtensions

class LockRecordCell: UICollectionViewCell {

    private let contentBUtton = UIButton(type: .custom)
    private let topSeparator = UIView()
    private let leftSeparator = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .clear
        backgroundColor = .clear
        contentBUtton.isUserInteractionEnabled = false
        contentBUtton.setImage(UIImage(named: "safe4_unsel_20"), for: .normal)
        contentBUtton.setImage(UIImage(named: "safe4_sel_20")?.withTintColor(.themeIssykBlue), for: .selected)
        contentBUtton.setImage(UIImage(named: "safe4_disable_20")?.withTintColor(.themeLightGray), for: .disabled)
        contentBUtton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
        contentBUtton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
        contentBUtton.titleLabel?.font = .subhead2
        contentBUtton.titleLabel?.numberOfLines = 0
        contentBUtton.setTitleColor(.themeBlue, for: .normal)
//        contentBUtton.setTitleColor(.black, for: .selected)
        contentBUtton.setTitleColor(.lightGray, for: .disabled)
        contentView.addSubview(contentBUtton)
        contentBUtton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.addSubview(topSeparator)
        topSeparator.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(1)
        }

        topSeparator.backgroundColor = .themeSteel10

        contentView.addSubview(leftSeparator)
        leftSeparator.snp.makeConstraints { maker in
            maker.leading.top.bottom.equalToSuperview()
            maker.width.equalTo(1)
        }

        leftSeparator.backgroundColor = .themeSteel10
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        contentBUtton.isEnabled = true
        contentBUtton.isSelected = false
        contentBUtton.setTitle(nil, for: .normal)
    }
    
    func bind(item: SuperNodeDetailViewModel.LockRecoardItem) {
        contentBUtton.isEnabled = item.isEnabledSlect
        contentBUtton.isSelected = item.isSlected
        let title = "ID:\(item.record.id)\n\(item.record.amount.safe4FomattedAmount) SAFE"
        contentBUtton.setTitle(title, for: .normal)
    }
}
