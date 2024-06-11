import Foundation
import UIKit
import RxSwift
import SnapKit
import ThemeKit
import ComponentKit
import MarketKit

class LiquidityTickInputCardView: UIView {
    private let labelHeight: CGFloat = 20
    private let disposeBag = DisposeBag()
    private let titleLabel = UILabel()
    private let amountTextView = SingleLineFormTextView()
    private let pairLabel = UILabel()
    private let cardView = CardView(insets: .zero)
    private let minusButton = UIButton(frame: .zero)
    private let plusButton = UIButton(frame: .zero)
    
    private var autocompleteView: LiquidityTickInputAccessoryView?
    
    override var inputAccessoryView: UIView? {
        autocompleteView
    }

    override var canBecomeFirstResponder: Bool {
        autocompleteView != nil
    }
    
    private let viewModel: LiquidityTickInputCardViewModel
    
    init(title: String, viewModel: LiquidityTickInputCardViewModel) {
        self.viewModel = viewModel
        
        super.init(frame: .zero)
        backgroundColor = .clear

        autocompleteView = LiquidityTickInputAccessoryView(frame: .zero)
        autocompleteView?.heightValue = 44
        autocompleteView?.onSelect = { [weak self] type in self?.setTickRange(type: type) }
        
        addSubview(cardView)
        
        cardView.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview()
            maker.top.bottom.equalToSuperview()
        }
        
        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { maker in
            maker.leading.equalToSuperview().inset(CGFloat.margin4)
            maker.trailing.equalToSuperview().inset(CGFloat.margin4)
            maker.top.equalToSuperview().inset(CGFloat.margin4)
            maker.height.equalTo(labelHeight)
        }
        
        cardView.addSubview(pairLabel)
        pairLabel.snp.makeConstraints { maker in
            maker.leading.equalToSuperview().inset(CGFloat.margin4)
            maker.trailing.equalToSuperview().inset(CGFloat.margin4)
            maker.bottom.equalToSuperview().inset(CGFloat.margin4)
            maker.height.equalTo(labelHeight)
        }
        
        cardView.addSubview(minusButton)
        minusButton.snp.makeConstraints { maker in
            maker.leading.equalToSuperview().inset(CGFloat.margin6)
            maker.top.equalTo(titleLabel.snp.bottom)
            maker.bottom.equalTo(pairLabel.snp.top)
            maker.width.equalTo(24)
        }
        
        cardView.addSubview(amountTextView)
        amountTextView.snp.makeConstraints { maker in
            maker.leading.equalTo(minusButton.snp.trailing).inset(CGFloat.margin6)
            maker.top.equalTo(titleLabel.snp.bottom)
            maker.bottom.equalTo(pairLabel.snp.top)
        }
        
        cardView.addSubview(plusButton)
        plusButton.snp.makeConstraints { maker in
            maker.leading.equalTo(amountTextView.snp.trailing).inset(CGFloat.margin6)
            maker.trailing.equalToSuperview().inset(CGFloat.margin6)
            maker.top.equalTo(titleLabel.snp.bottom)
            maker.bottom.equalTo(pairLabel.snp.top)
            maker.width.equalTo(24)
        }
        
        titleLabel.textAlignment = .center
        titleLabel.font = .subhead1I
        titleLabel.textColor = .themeGray
        titleLabel.text = title
        
        minusButton.setImage(UIImage(named: "circle_minus_24"), for: .normal)
        minusButton.addTarget(self, action: #selector(onTapMinus), for: .touchUpInside)
        
        plusButton.setImage(UIImage(named: "circle_plus_24"), for: .normal)
        plusButton.addTarget(self, action: #selector(onTapPlus), for: .touchUpInside)
        
        amountTextView.font = .headline1
        amountTextView.textColor = .themeLeah
        amountTextView.placeholder = "0.0"
        amountTextView.keyboardType = .decimalPad
        amountTextView.textAlignment = .center
        amountTextView.onChangeText = { [weak self] in self?.viewModel.onChange(price: $0) }
        amountTextView.onChangeEditing = { [weak self] in self?.sync(editing: $0)  }
        pairLabel.textAlignment = .center
        pairLabel.font = .subhead1
        pairLabel.textColor = .themeGray
        
        subscribeToViewModel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private func subscribeToViewModel() {
        subscribe(disposeBag, viewModel.readOnlyDriver) { [weak self] in self?.set(readOnly: $0) }
        subscribe(disposeBag, viewModel.priceDriver) { [weak self] in self?.sync(price: $0) }
        subscribe(disposeBag, viewModel.pairDriver) { [weak self] in self?.sync(pair: $0) }
    }
    
    override func becomeFirstResponder() -> Bool {
        amountTextView.becomeFirstResponder()
    }
    
    /// safe
    private func split(str: String, decimal: Int) -> String? {
        let components = str.split(separator: ".")
        if let integerPart = components.first, let decimalPart = components.last, decimalPart.count > 8 {
            let truncatedDecimalPart = String(decimalPart.prefix(decimal))
            let result = integerPart + "." + truncatedDecimalPart
            return result
        }
        return nil
    }
    
    @objc func onTapMinus() {
        viewModel.onTapMinusTick()
    }
    
    @objc func onTapPlus() {
        viewModel.onTapPlusTick()
    }
}

private extension LiquidityTickInputCardView {
    
    func sync(editing: Bool) {
//        viewModel.viewIsEditing = editing
    }
    
    func set(readOnly: Bool) {
        minusButton.isHidden = readOnly
        plusButton.isHidden = readOnly
        amountTextView.isEditable = !readOnly
    }
    
    func setTickRange(type: RangeType) {
        viewModel.setTickRange(type: type)
        amountTextView.endEditing(true)
    }
    
    func sync(pair: String?) {
        pairLabel.text = pair
    }
    
    func sync(price: String?) {
        amountTextView.text = split(str: price ?? "", decimal: 4) ?? price
    }
}
