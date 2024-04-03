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
    
    private let ratioView = RatioView()

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

        addSubview(separatorView3)
        separatorView3.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview()
            maker.top.equalTo(cardView.snp.bottom).inset(-CGFloat.margin12)
            maker.height.equalTo(CGFloat.heightOneDp)
        }
        separatorView3.backgroundColor = .themeSteel20
        
        addSubview(ratioView)
        ratioView.snp.makeConstraints { maker in
            maker.top.equalTo(separatorView3.snp.bottom).inset(-CGFloat.margin12)
            maker.leading.trailing.equalToSuperview()
            maker.height.equalTo(RatioView.height)
        }
        
        addSubview(removeButton)
        removeButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.top.equalTo(ratioView.snp.bottom).inset(-CGFloat.margin12)
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
        onTapRemove?(item, ratioView.seletedRatio)
    }
    
    static func height() -> CGFloat {
        var height: CGFloat = margins.height

        height += PairTokenView.height * 4 + 10 + RatioView.height
        
        height += CGFloat.heightOneDp * 3
        
        return height
    }
}

enum RemoveRatio: BigUInt, CaseIterable {
    case ratio_25 = 25
    case ratio_50 = 50
    case ratio_75 = 75
    case ratio_100 = 100
    
    var title: String {
        switch self {
        case .ratio_25: return "25%"
        case .ratio_50: return "50%"
        case .ratio_75: return "75%"
        case .ratio_100: return "100%"
        }
    }
}

class RatioView: UIView {
    static let height: CGFloat = 50
    static let width = (UIScreen.main.bounds.width - 4 * CGFloat.margin12) / CGFloat(RemoveRatio.allCases.count)
    private let buttonStackView = UIStackView()
    private(set) var seletedRatio: BigUInt
    private var primaryButtons = [PrimaryButtonComponent]()
    init() {
        seletedRatio = RemoveRatio.ratio_100.rawValue
       
        super.init(frame: .zero)
        
        addSubview(buttonStackView)
        buttonStackView.snp.makeConstraints { maker in
            maker.top.equalToSuperview().offset(CGFloat.margin12)
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.bottom.equalToSuperview().inset(CGFloat.margin12)
        }

        buttonStackView.axis = .horizontal
        buttonStackView.alignment = .fill
        buttonStackView.spacing = .margin12
        
        primaryButtons.removeAll()
        for (index, item) in RemoveRatio.allCases.enumerated() {
            let component = PrimaryButtonComponent()
            let accessory = PrimaryButton.AccessoryType.none
            component.button.set(style: .gray, accessoryType: accessory)
            component.button.setTitle(item.title, for: .normal)
            component.button.titleLabel?.font = UIFont.systemFont(ofSize: 13)
            component.button.tag = index
            component.onTap = { [weak self] in
                self?.seletedRatio = item.rawValue
                self?.reloadButtonsStatus()
            }
            
            component.snp.makeConstraints { make in
                make.height.equalTo(RatioView.height)
                make.width.equalTo((RatioView.width - CGFloat.margin12))
            }
            buttonStackView.addArrangedSubview(component)
            primaryButtons.append(component)
        }
        reloadButtonsStatus()
       
    }
    
    private func reloadButtonsStatus() {
        
        for (index, component) in primaryButtons.enumerated() {
            let isSelected = seletedRatio == RemoveRatio.allCases[index].rawValue
            component.button.set(style: isSelected ? .yellow : .gray, accessoryType: .none)

        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
