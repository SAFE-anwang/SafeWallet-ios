import ComponentKit
import RxCocoa
import RxSwift
import SnapKit
import ThemeKit
import UIKit
import UIExtensions

class SuperNodeSafeVoteCell: BaseThemeCell {
    private let voteButton = UIButton(type: .custom)
    private let amountTitleLabel = UILabel()
    private let balanceLabel = UILabel()
    private let formValidatedView: FormValidatedView
    private let inputStackView = InputStackView()
    private let inputWarningLabel = UILabel()
    private let deleteView = InputSecondaryCircleButtonWrapperView()
    private let maxButton = UIButton(type: .custom)
    private var balance: Decimal?
    
    var safeVote: ((Decimal) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        
        formValidatedView = FormValidatedView(contentView: inputStackView, padding: UIEdgeInsets(top: 0, left: .margin16, bottom: 0, right: .margin16))
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        set(backgroundStyle: .lawrence, isFirst: false, isLast: true)
        addEndEditingTapGesture()
        amountTitleLabel.text = "数量"
        amountTitleLabel.font = .subhead1
        wrapperView.addSubview(amountTitleLabel)
        amountTitleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        balanceLabel.font = .subhead1
        balanceLabel.textAlignment = .right
        wrapperView.addSubview(balanceLabel)
        balanceLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin24)
        }
        
        wrapperView.addSubview(formValidatedView)
        formValidatedView.snp.makeConstraints { make in
            make.top.equalTo(amountTitleLabel.snp.bottom).offset(CGFloat.margin8)
            make.leading.equalToSuperview()
            make.height.equalTo(CGFloat.margin40)
        }

        deleteView.button.set(image: UIImage(named: "trash_20"))
        deleteView.onTapButton = { [weak self] in self?.onTapDelete() }
        
        inputStackView.placeholder = "输入数量"
        inputStackView.autocapitalizationType = .none
        inputStackView.autocorrectionType = .no
        inputStackView.keyboardType = .decimalPad
        inputStackView.appendSubview(deleteView)
        
        maxButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        maxButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        maxButton.setTitleColor(.themeIssykBlue, for: .normal)
        maxButton.setTitle("最大", for: .normal)
        maxButton.titleLabel?.font = .headline2
        maxButton.addTarget(self, action: #selector(maxValue), for: .touchUpInside)
        wrapperView.addSubview(maxButton)
        maxButton.snp.makeConstraints { make in
            make.centerY.equalTo(formValidatedView)
            make.leading.equalTo(formValidatedView.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        inputWarningLabel.isHidden = true
        inputWarningLabel.font = .subhead2
        inputWarningLabel.textColor = .red
        inputWarningLabel.text = "超出可用数量"
        wrapperView.addSubview(inputWarningLabel)
        inputWarningLabel.snp.makeConstraints { make in
            make.top.equalTo(formValidatedView.snp.bottom).offset(CGFloat.margin4)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        addVoteButton()
        wrapperView.addSubview(voteButton)
        voteButton.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.margin16)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.height.equalTo(CGFloat.margin40)
        }

        inputStackView.onChangeText = { [weak self] text in
            self?.handleChange(text: text)
        }
        
        syncButtonStates()
    }
    
    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addVoteButton() {
        voteButton.cornerRadius = 6
        voteButton.setTitle("投票", for: .normal)
        voteButton.titleLabel?.font = .headline2
        voteButton.setTitleColor(.white, for: .normal)
        voteButton.setTitleColor(.gray, for: .disabled)
        voteButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 20)
        voteButton.setBackgroundColor(.themeIssykBlue, for: .normal)
        voteButton.setBackgroundColor(.lightGray.withAlphaComponent(0.4) , for: .disabled)
        voteButton.addTarget(self, action: #selector(vote), for: .touchUpInside)
    }
    
    @objc 
    private func vote() {
        let amount = AmountDecimalParser().parseAnyDecimal(from: inputStackView.text)
        inputStackView.text = amount?.description
        guard let balance, let amount else{ return }
        guard amount <= balance else{
            inputWarningLabel.isHidden = false
            return
        }
        safeVote?(amount)
    }
    
    @objc 
    private func maxValue() {
        inputStackView.text = "\(balance ?? 0.00)"
        syncButtonStates()
    }
    
    func height() -> CGFloat {
        170
    }
    
    func update(balance:Decimal?) {
        self.balance = balance
        balanceLabel.text = "可用数量: \(balance?.safe4FormattedAmount ?? "0.00") SAFE"
    }
}

extension SuperNodeSafeVoteCell {
    private func onTapDelete() {
        inputStackView.text = nil
        handleChange(text: nil)
    }
    
    private func handleChange(text: String?) {
        inputWarningLabel.isHidden = true
        syncButtonStates()
    }

    private func syncButtonStates() {

        if let text = inputStackView.text, !text.isEmpty {
            deleteView.isHidden = false
            voteButton.isEnabled = true
        } else {
            deleteView.isHidden = true
            voteButton.isEnabled = false
        }
    }
}
