import UIKit
import BigInt

class LiquidityInputAccessoryView: UIView {
    private let autocompleteView = FilterView(buttonStyle: .default)
    
    private let inputRanges = [InputRange(value: 0.25, text: "25%"),
                               InputRange(value: 0.5,  text: "50%"),
                               InputRange(value: 0.75, text: "75%"),
                               InputRange(value: 1,    text: "100%")]
    
    private var heightConstraint: NSLayoutConstraint?
    
    var heightValue: CGFloat = 0 {
        didSet {
            heightConstraint?.constant = heightValue
        }
    }
    
    var selected: InputRange?
    
    var onSelect: ((Float) -> Void)?
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(autocompleteView)
        autocompleteView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(FilterView.height)
        }
        
        autocompleteView.reload(filters: inputRanges.map{ FilterView.ViewItem.item(title: $0.text)})
        autocompleteView.onSelect = { [weak self] in self?.onTap(at: $0) }
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        var heightConstraint: NSLayoutConstraint?
        
        for constraint in constraints {
            if constraint.firstItem as? UIView == self, constraint.firstAttribute == .height, constraint.relation == .equal {
                heightConstraint = constraint
                break
            }
        }
        
        self.heightConstraint = heightConstraint
        self.heightConstraint?.constant = heightValue
    }
    
    private func onTap(at index: Int) {
        selected = inputRanges[index]
        let value = inputRanges[index].value
        onSelect?(value)
    }
    
    func setDefaultSelected() {
        autocompleteView.select(index: inputRanges.count - 1)
        selected = inputRanges.last
    }
    
    func setAutoDeselect(auto: Bool) {
        autocompleteView.autoDeselect = auto
    }
    
    func setBackgroundColor(_ color: UIColor) {
        autocompleteView.backgroundColor = color
    }
}

extension LiquidityInputAccessoryView {
    struct InputRange: Equatable {
        let value: Float
        let text: String
    }
}
