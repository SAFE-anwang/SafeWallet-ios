import UIKit
import Foundation
import SnapKit
import ThemeKit
import ComponentKit
import BigInt

class LiquidityRemoveConfirmView: UIView {
    
    private static let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)

    private let cardView = CardView(insets: .zero)
    private let tokenAView = PairTokenView()
    private let tokenBView = PairTokenView()
    private let liquidityNumLabel = UILabel()
    private let separatorView1 = UIView()
    private let separatorView2 = UIView()
    private let separatorView3 = UIView()
        
    private let autocompleteView = LiquidityInputAccessoryView(frame: .zero)
    private let removeButton = PrimaryButton()
    
    private var onTapRemove: ((LiquidityRecordViewModel.RecordItem, BigUInt) -> ())?
    private var viewItem: LiquidityRecordViewModel.RecordItem?
    
    
    init() {
        super.init(frame: .zero)
        
        backgroundColor = .clear
        
        addSubview(cardView)
        cardView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview().inset(Self.margins)
        }
        
        liquidityNumLabel.font = .headline2
        liquidityNumLabel.textColor = .themeLeah
        
        removeButton.set(style: .yellow)
        removeButton.setTitle("liquidity.remove".localized, for: .normal)
        removeButton.addTarget(self, action: #selector(tapRemove), for: .touchUpInside)
                
        autocompleteView.heightValue = 44
        autocompleteView.setDefaultSelected()
        addSubview(autocompleteView)
        autocompleteView.snp.makeConstraints { maker in
            maker.top.equalTo(cardView.snp.bottom).inset(-CGFloat.margin12)
            maker.leading.trailing.equalToSuperview()
            maker.height.equalTo(44)
        }
        
        addSubview(removeButton)
        removeButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.top.equalTo(autocompleteView.snp.bottom).inset(-CGFloat.margin12)
            maker.height.equalTo(PairTokenView.height)
        }
        
        cardView.contentView.addSubview(tokenAView)
        tokenAView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
            maker.height.equalTo(PairTokenView.height)
        }

        cardView.contentView.addSubview(separatorView1)
        separatorView1.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.bottom.equalTo(tokenAView).offset(PairTokenView.expandedMargin)
            maker.height.equalTo(CGFloat.heightOneDp)
        }

        separatorView1.backgroundColor = .themeSteel20

        cardView.contentView.addSubview(tokenBView)
        tokenBView.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview()
            maker.top.equalTo(separatorView1.snp.bottom)
            maker.height.equalTo(PairTokenView.height)
        }
        
        cardView.contentView.addSubview(separatorView2)
        separatorView2.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.top.equalTo(tokenBView.snp.bottom)
            maker.height.equalTo(CGFloat.heightOneDp)
        }

        separatorView2.backgroundColor = .themeSteel20
        
        cardView.contentView.addSubview(liquidityNumLabel)
        liquidityNumLabel.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.top.equalTo(separatorView2.snp.bottom)
            maker.height.equalTo(PairTokenView.height)
            maker.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func bind(viewItem: LiquidityRecordViewModel.RecordItem, onTapRemove: @escaping (LiquidityRecordViewModel.RecordItem, _ seletedRatio: BigUInt) -> ()) {
        
        self.onTapRemove = onTapRemove
        self.viewItem = viewItem
        tokenAView.bind(iconUrl: viewItem.tokenA.coin.imageUrl,
                        name: viewItem.tokenA.coin.code,
                        blockchainBadge: viewItem.tokenA.protocolName ?? viewItem.tokenA.type.description,
                        amount: viewItem.amountAStr
        )
        
        tokenBView.bind(iconUrl: viewItem.tokenB.coin.imageUrl,
                        name: viewItem.tokenB.coin.code,
                        blockchainBadge: viewItem.tokenB.protocolName ?? viewItem.tokenB.type.description,
                        amount: viewItem.amountBStr
        )
        
        liquidityNumLabel.text = viewItem.liquidityDec
        
    }
    
    @objc private func tapRemove() {
        guard let item = viewItem else { return }
        guard let value = autocompleteView.selected?.value else { return }
        onTapRemove?(item, BigUInt(Int(value * 100)))
    }
}

