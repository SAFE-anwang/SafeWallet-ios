import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
import UIExtensions

class AddLockDaysRecordCell: UITableViewCell {
    private let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let cardView = CardView(insets: .zero)
    private let lockIdView = ItemView()
    private let lockedDayView = ItemView()
    private let maxLockDayView = ItemView()

    private let daysLabel = UILabel()
    private let minusButton = UIButton(type: .custom)
    private let plusButton = UIButton(type: .custom)
    private let addButton = PrimaryButton()

    var toMinus: (() -> Void)?
    var toPlus: (() -> Void)?
    var toAdd: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(margins)
        }
        
        lockIdView.titleLabel.text = "safe_zone.safe4.vote.record.id".localized
        lockedDayView.titleLabel.text = "safe_zone.safe4.node.locked.days".localized
        maxLockDayView.titleLabel.text = "safe_zone.safe4.node.locked.days.max".localized
        
        cardView.addSubview(lockIdView)
        lockIdView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.leading.trailing.equalToSuperview()
        }
        
        cardView.addSubview(lockedDayView)
        lockedDayView.snp.makeConstraints { make in
            make.top.equalTo(lockIdView.snp.bottom).offset(CGFloat.margin8)
            make.leading.trailing.equalToSuperview()
        }
        
        cardView.addSubview(maxLockDayView)
        maxLockDayView.snp.makeConstraints { make in
            make.top.equalTo(lockedDayView.snp.bottom).offset(CGFloat.margin8)
            make.leading.trailing.equalToSuperview()
        }
        
        daysLabel.font = .subhead2
        daysLabel.textAlignment = .center
        cardView.addSubview(daysLabel)
        daysLabel.snp.makeConstraints { make in
            make.top.equalTo(maxLockDayView.snp.bottom).offset(CGFloat.margin16)
            make.centerX.equalToSuperview()
        }
        
        minusButton.setImage(UIImage(named: "circle_minus_24"), for: .normal)
        minusButton.addTarget(self, action: #selector(minusAction), for: .touchUpInside)
        cardView.addSubview(minusButton)
        minusButton.snp.makeConstraints { make in
            make.trailing.equalTo(daysLabel.snp.leading).inset(-CGFloat.margin8)
            make.size.equalTo(CGSize(width: 24, height: 24))
            make.centerY.equalTo(daysLabel)
        }
        
        plusButton.setImage(UIImage(named: "circle_plus_24"), for: .normal)
        plusButton.addTarget(self, action: #selector(plusAction), for: .touchUpInside)
        cardView.addSubview(plusButton)
        plusButton.snp.makeConstraints { make in
            make.centerY.equalTo(daysLabel)
            make.size.equalTo(CGSize(width: 24, height: 24))
            make.leading.equalTo(daysLabel.snp.trailing).offset(CGFloat.margin8)
        }
        
        addButton.setTitle("safe_zone.safe4.node.locked.days.add.btn.title".localized, for: .normal)
        addButton.addTarget(self, action: #selector(addAction), for: .touchUpInside)
        addButton.set(style: .yellow)
        cardView.addSubview(addButton)
        addButton.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(CGFloat.heightButton)
            make.leading.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(info: AddLockDaysViewModel.LockInfo) {
        lockIdView.valueLabel.text = info.lockID.description
        lockedDayView.valueLabel.text = info.lockedDays.description + "safe_zone.safe4.node.locked.days.title".localized
        maxLockDayView.valueLabel.text = info.maxLockDays.description + "safe_zone.safe4.node.locked.days.title".localized
        daysLabel.text = "\(info.selectedLockedDays.description)" + "safe_zone.safe4.node.locked.days.title".localized
    }
    
    @objc func minusAction() {
        toMinus?()
    }
    
    @objc func plusAction() {
        toPlus?()
    }
    
    @objc func addAction() {
        toAdd?()
    }
        
    static func height() -> CGFloat {
        200
    }
}

fileprivate class ItemView: UIView {
    let titleLabel = UILabel()
    let valueLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        titleLabel.font = .subhead2
        titleLabel.textColor = .themeGray
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(CGFloat.margin8)
        }
        
        valueLabel.font = .subhead2
        valueLabel.textAlignment = .right
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.trailing.equalToSuperview().inset(CGFloat.margin8)
            make.leading.equalTo(titleLabel.snp.trailing).offset(CGFloat.margin8)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
