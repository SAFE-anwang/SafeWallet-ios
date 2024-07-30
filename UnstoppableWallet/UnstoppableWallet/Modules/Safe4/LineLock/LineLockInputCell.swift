import UIKit
import ThemeKit
import SnapKit
import RxSwift

class LineLockInputCell: UITableViewCell {
    
    private let disposeBag = DisposeBag()
    private let anInputView: InputView
    private let titleLabel: UILabel

    private let viewModel: LineLockInputViewModel
    private let inputType: LineLockInputViewModel.InputType
        
    init(viewModel: LineLockInputViewModel, inputType: LineLockInputViewModel.InputType) {
        self.viewModel = viewModel
        self.inputType = inputType
        
        anInputView = InputView(singleLine: true)
        titleLabel = UILabel(frame: .zero)
        titleLabel.font = UIFont.systemFont(ofSize: 12)
        titleLabel.textColor = .themeGray
        
        super.init(style: .default, reuseIdentifier: nil)
        
        backgroundColor = .clear
        selectionStyle = .none
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { maker in
            maker.leading.trailing.equalTo(16)
            maker.top.equalTo(5)
        }
        
        contentView.addSubview(anInputView)
        anInputView.snp.makeConstraints { maker in
            maker.top.equalTo(titleLabel.snp.bottom)
            maker.bottom.leading.trailing.equalToSuperview()
        }
        
                
        
        anInputView.onChangeText = { [weak self] in
            switch self?.inputType {
            case .amount:
                self?.anInputView.isValidText = { [weak self] in self?.viewModel.isValid(value: $0) ?? true }
                self?.viewModel.onChange(amount: $0)
            case .startMonth:
                self?.anInputView.isValidText = { [weak self] in self?.viewModel.isValid(month: $0) ?? true }
                self?.viewModel.onChange(startMonth: $0)
            case .intervalMonth:
                self?.anInputView.isValidText = { [weak self] in self?.viewModel.isValid(month: $0) ?? true }
                self?.viewModel.onChange(intervalMonth: $0)
            case .none: break
            }
        }
        

        switch inputType {
        case .amount:
            anInputView.keyboardType = .decimalPad
            anInputView.inputPlaceholder = "safe_lock.amount.unlock".localized
            subscribe(disposeBag, viewModel.amountDriver) { [weak self] in self?.set(amount: $0) }
        case .startMonth:
            anInputView.keyboardType = .numberPad
            anInputView.inputPlaceholder = "safe_lock.month.start".localized
            subscribe(disposeBag, viewModel.startMonthDriver) { [weak self] in self?.set(startMonth: $0) }
        case .intervalMonth:
            anInputView.keyboardType = .numberPad
            anInputView.inputPlaceholder = "safe_lock.month.interval".localized
            subscribe(disposeBag, viewModel.intervalMonthDriver) { [weak self] in self?.set(intervalMonth: $0) }
        }
        
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        anInputView.becomeFirstResponder()
    }
    
    private func set(amount: Decimal?) {
        titleLabel.text = amount != nil ? "safe_lock.amount.unlock".localized : nil
        guard let amount = amount else { return anInputView.inputText = nil}
        anInputView.inputText = "\(amount)"
    }

    private func set(startMonth: Int?) {
        titleLabel.text = startMonth != nil ? "safe_lock.month.start".localized : nil
        guard let startMonth = startMonth else { return anInputView.inputText = nil }
        anInputView.inputText = "\(startMonth)"
    }
    
    private func set(intervalMonth: Int?) {
        titleLabel.text = intervalMonth != nil ? "safe_lock.month.interval".localized : nil
        guard let intervalMonth = intervalMonth else { return anInputView.inputText = nil }
        anInputView.inputText = "\(intervalMonth)"
    }
    
    func set(cautionType: CautionType?) {
        anInputView.set(cautionType: cautionType)
    }
    
    func height(containerWidth: CGFloat) -> CGFloat {
        anInputView.height(containerWidth: containerWidth) + (titleLabel.text == nil ? 0 : 20)
    }
}

