import Foundation
import UIKit
import RxSwift
import SnapKit
import ThemeKit
import ComponentKit

class LiquidityTickInputCell: UITableViewCell {
    static let cellHeight: CGFloat = 180
    private let inputCardViewHeight: CGFloat = 80
    private let disposeBag = DisposeBag()
    private let lowerTickInputCardView: LiquidityTickInputCardView
    private let upperTickInputCardView: LiquidityTickInputCardView
    private let currentTickInputCardView: LiquidityTickInputCardView

    private let cardView = CardView(insets: .zero)
    
    init(lowerTickViewModel: LiquidityTickInputCardViewModel, upperTickViewModel: LiquidityTickInputCardViewModel, currentTickViewModel: LiquidityTickInputCardViewModel) {
        lowerTickInputCardView = LiquidityTickInputCardView(title: "liquidity.tick.price.min".localized, viewModel: lowerTickViewModel)
        upperTickInputCardView = LiquidityTickInputCardView(title: "liquidity.tick.price.max".localized, viewModel: upperTickViewModel)
        currentTickInputCardView = LiquidityTickInputCardView(title: "liquidity.tick.price.current".localized, viewModel: currentTickViewModel)
        
        super.init(style: .default, reuseIdentifier: nil)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(lowerTickInputCardView)
        lowerTickInputCardView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(inputCardViewHeight)
        }
        
        contentView.addSubview(upperTickInputCardView)
        upperTickInputCardView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.leading.equalTo(lowerTickInputCardView.snp.trailing).offset(CGFloat.margin16)
            make.height.equalTo(inputCardViewHeight)
            make.width.equalTo(lowerTickInputCardView.snp.width)
        }
        
        contentView.addSubview(currentTickInputCardView)
        currentTickInputCardView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(inputCardViewHeight)
            make.bottom.equalToSuperview().inset(CGFloat.margin8)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func becomeFirstResponder() -> Bool {
        lowerTickInputCardView.becomeFirstResponder()
    }
}
