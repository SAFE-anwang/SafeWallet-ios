import UIKit

struct TickRange {
    let range: RangeType
    let text: String
}

enum RangeType: Equatable {
    case full
    case range(value: Decimal)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.range(lh), .range(rh)): return lh == rh
        case (.full, .full): return true
        default: return false
        }
    }
}

class LiquidityTickInputAccessoryView: UIView {
    private let separatorView = UIView()
    private let autocompleteView = FilterView(buttonStyle: .default)
    
    private let tickRanges = [TickRange(range: .range(value: 0.1), text: "10%"),
                              TickRange(range: .range(value: 0.2), text: "20%"),
                              TickRange(range: .range(value: 0.5), text: "50%"),
                              TickRange(range: .full, text: "liquidity.tick.full.range".localized)]
    
    private var heightConstraint: NSLayoutConstraint?
    var heightValue: CGFloat = 0 {
        didSet {
            heightConstraint?.constant = heightValue
        }
    }
    
    var onSelect: ((RangeType) -> Void)?
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(separatorView)
        separatorView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(CGFloat.heightOneDp)
        }
        separatorView.backgroundColor = .themeSteel20
        
        addSubview(autocompleteView)
        autocompleteView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(FilterView.height)
        }
        
        autocompleteView.autoDeselect = true
        autocompleteView.reload(filters: tickRanges.map{ FilterView.ViewItem.item(title: $0.text)})
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
        let range = tickRanges[index].range
        onSelect?(range)
    }
}
