import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
import UIExtensions

class Safe4NodeJoinPartnerViewCell: BaseThemeCell {
    private let joinButton = UIButton(type: .custom)
    private let slider: UISlider
    
    private let amountTitleLabel = UILabel()
    private let amountLabel = UILabel()
    
    private let balanceTitleLabel = UILabel()
    private let balanceLabel = UILabel()
    
    private let balanceCautionLabel = UILabel()
    
    private var step: Float?
    private var minValue: Float?
    private var balance: Decimal?

    
    var joinPartner: ((Float) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        slider = UISlider()
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        set(backgroundStyle: .lawrence, isFirst: false, isLast: true)
        
        amountTitleLabel.text = "数量"
        amountTitleLabel.font = .subhead1
        wrapperView.addSubview(amountTitleLabel)
        amountTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        amountLabel.text = "0.00 SAFE"
        amountLabel.font = .headline2
        wrapperView.addSubview(amountLabel)
        amountLabel.snp.makeConstraints { make in
            make.top.equalTo(amountTitleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        balanceTitleLabel.text = "账户余额"
        balanceTitleLabel.font = .subhead1
        balanceTitleLabel.textAlignment = .right
        wrapperView.addSubview(balanceTitleLabel)
        balanceTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        balanceLabel.text = "0.00 SAFE"
        balanceLabel.font = .headline2
        balanceLabel.textAlignment = .right
        wrapperView.addSubview(balanceLabel)
        balanceLabel.snp.makeConstraints { make in
            make.top.equalTo(balanceTitleLabel.snp.bottom).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        wrapperView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.top.equalTo(amountLabel.snp.bottom).offset(CGFloat.margin12)
        }
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        
        balanceCautionLabel.isHidden = true
        balanceCautionLabel.font = .subhead2
        balanceCautionLabel.textColor = .red
        balanceCautionLabel.text = "账户余额不足"
        wrapperView.addSubview(balanceCautionLabel)
        balanceCautionLabel.snp.makeConstraints { make in
            make.top.equalTo(slider.snp.bottom).inset(CGFloat.margin6)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        addJoinButton()
        wrapperView.addSubview(joinButton)
        joinButton.snp.makeConstraints { make in
            make.top.equalTo(balanceCautionLabel.snp.bottom).offset(CGFloat.margin6)
            make.bottom.equalToSuperview().inset(CGFloat.margin12)
            make.height.equalTo(32)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
        }
    }
    
    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addJoinButton() {
        joinButton.cornerRadius = 6
        joinButton.setTitle("成为合伙人", for: .normal)
        joinButton.titleLabel?.font = .headline2
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.setTitleColor(.gray, for: .disabled)
        joinButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 20)
        joinButton.setBackgroundColor(.themeIssykBlue, for: .normal)
        joinButton.setBackgroundColor(.lightGray , for: .disabled)
        joinButton.addTarget(self, action: #selector(join), for: .touchUpInside)
    }
    
    @objc 
    private func join() {
        guard let balance, balance >= Decimal(Double(slider.value)) else {
            balanceCautionLabel.isHidden = false
            return
        }
        joinPartner?(slider.value)
    }

    func bind(minValue: Float, step: Float, minimumValue: Float, maximumValue: Float, balance: Decimal?) {
        self.step = step
        self.minValue = minValue
        self.balance = balance
        slider.minimumValue = minimumValue
        slider.maximumValue = maximumValue
        slider.value = minValue
        amountLabel.text = "\(minValue) SAFE"
        balanceLabel.text = "\(balance?.safe4FormattedAmount ?? "--") SAFE"
    }
    
    @objc
    private func sliderValueChanged(_ sender: UISlider) {
        balanceCautionLabel.isHidden = true
        guard let step, let minValue else{ return }
        guard sender.value >= minValue else {
            sender.value = minValue
            return
        }
        let roundedValue = round(sender.value / step) * step
        sender.value = roundedValue
        amountLabel.text = "\(roundedValue) SAFE"
    }
    
    func height() -> CGFloat {
        180
    }
}

