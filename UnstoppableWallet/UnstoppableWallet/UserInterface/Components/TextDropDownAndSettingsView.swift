import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class TextDropDownAndSettingsView: UIView {
    static let height: CGFloat = .heightSingleLineCell

    private let dropdownButton = SecondaryButton()

    private let stackView = UIStackView()
    private let selectorButton = SelectorButton()
    private let settingsButton = SecondaryCircleButton()
    private let transactionsButton = SecondaryCircleButton()
    private let liquidityRecordButton = SecondaryCircleButton()

    var onTapDropDown: (() -> ())?
    var onTapSettings: (() -> ())?
    var onTapSelector: ((Int) -> ())?
    var onTapTransactions: (() -> ())?
    var onTapLiquidityRecord: (() -> ())?
    
    var isEnabledTransactions: Bool = true {
        didSet {
            transactionsButton.isHidden = !isEnabledTransactions
            transactionsButton.isEnabled = isEnabledTransactions
        }
    }
    
    var isEnabledLiquidity: Bool = true {
        didSet {
            liquidityRecordButton.isHidden = !isEnabledLiquidity
            liquidityRecordButton.isEnabled = isEnabledLiquidity
        }
    }
    
    init() {
        super.init(frame: .zero)

        addSubview(dropdownButton)
        dropdownButton.snp.makeConstraints { maker in
            maker.leading.centerY.equalToSuperview()
        }

        dropdownButton.set(style: .transparent, image: UIImage(named: "arrow_small_down_20"))
        dropdownButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dropdownButton.addTarget(self, action: #selector(onTapDropDownButton), for: .touchUpInside)

        addSubview(stackView)
        stackView.snp.makeConstraints { maker in
            maker.trailing.equalToSuperview().inset(CGFloat.margin16)
            maker.centerY.equalTo(dropdownButton)
        }

        stackView.axis = .horizontal
        stackView.spacing = .margin16

        stackView.addArrangedSubview(selectorButton)
        
        stackView.addArrangedSubview(liquidityRecordButton)
        stackView.addArrangedSubview(transactionsButton)
        stackView.addArrangedSubview(settingsButton)

        selectorButton.isHidden = true
        selectorButton.onSelect = { [weak self] in self?.onTapSelector?($0) }
        
        liquidityRecordButton.set(image: UIImage(named: "arrow_swap_approval_2_24"))
        liquidityRecordButton.addTarget(self, action: #selector(onTapLiquidityRecordButton), for: .touchUpInside)
        
        transactionsButton.set(image: UIImage(named: "filled_transaction_2n_24"))
        transactionsButton.addTarget(self, action: #selector(onTapTransactionsButton), for: .touchUpInside)

        settingsButton.set(image: UIImage(named: "manage_2_20"))
        settingsButton.addTarget(self, action: #selector(onTapSettingsButton), for: .touchUpInside)
        
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func onTapDropDownButton() {
        onTapDropDown?()
    }

    @objc private func onTapSettingsButton() {
        onTapSettings?()
    }
    
    @objc private func onTapTransactionsButton() {
        onTapTransactions?()
    }
    
    @objc private func onTapLiquidityRecordButton() {
        onTapLiquidityRecord?()
    }

    func bind(dropdownTitle: String?, settingsHidden: Bool = false) {
        dropdownButton.setTitle(dropdownTitle, for: .normal)
        settingsButton.isHidden = settingsHidden
    }

    func setSelector(items: [String]) {
        selectorButton.isHidden = items.isEmpty
        guard !items.isEmpty else {
            return
        }

        selectorButton.set(items: items)
    }

    func setSelector(index: Int) {
        selectorButton.setSelected(index: index)
    }

    func setSelector(isEnabled: Bool) {
        selectorButton.isEnabled = isEnabled
    }

}
