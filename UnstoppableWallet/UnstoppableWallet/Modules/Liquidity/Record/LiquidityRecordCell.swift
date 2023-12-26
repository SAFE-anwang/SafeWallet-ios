import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class LiquidityRecordCell: UITableViewCell {
    private static let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)

    private let cardView = CardView(insets: .zero)
    private let tokenAView = PairTokenView()
    private let tokenBView = PairTokenView()
    private let liquidityNumLabel = UILabel()
    private let separatorView1 = UIView()
    private let separatorView2 = UIView()
    private let separatorView3 = UIView()
    private let sendButton = PrimaryButton()
    
    private var onTapRemove: ((LiquidityRecordViewModel.RecordItem) -> ())?
    private var viewItem: LiquidityRecordViewModel.RecordItem?
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview().inset(Self.margins)
        }
        
        liquidityNumLabel.font = .headline2
        liquidityNumLabel.textColor = .themeLeah
        
        sendButton.set(style: .yellow)
        sendButton.setTitle("liquidity.remove".localized, for: .normal)
        sendButton.addTarget(self, action: #selector(tapRemove), for: .touchUpInside)
        
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
        }

        cardView.contentView.addSubview(separatorView3)
        separatorView3.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.top.equalTo(liquidityNumLabel.snp.bottom)
            maker.height.equalTo(CGFloat.heightOneDp)
        }
        separatorView3.backgroundColor = .themeSteel20
        
        cardView.contentView.addSubview(sendButton)
        sendButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin12)
            maker.bottom.equalToSuperview().inset(CGFloat.margin12)
            maker.height.equalTo(PairTokenView.height)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    @objc private func tapRemove() {
        guard let item = viewItem else { return }
        onTapRemove?(item)
    }
    
    func bind(viewItem: LiquidityRecordViewModel.RecordItem, onTapRemove: @escaping (LiquidityRecordViewModel.RecordItem) -> ()) {
        
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

    static func height() -> CGFloat {
        var height: CGFloat = margins.height

        height += PairTokenView.height * 4 + 10
        
        height += CGFloat.heightOneDp * 3
        
        return height
    }

}


class PairTokenView: UIView {
    static let height: CGFloat = 62
    static let expandedMargin: CGFloat = 6

    private let coinIconView = UIImageView()

    private let nameLabel = UILabel()
    private let blockchainBadgeView = BadgeView()

    private let bottomLeftLabel = UILabel()

    init() {
        super.init(frame: .zero)
        
        coinIconView.contentMode = .scaleAspectFit
        addSubview(coinIconView)
        coinIconView.snp.makeConstraints { maker in
            maker.leading.equalToSuperview().inset(CGFloat.margin16)
            maker.centerY.equalToSuperview()
            maker.size.equalTo(CGFloat.iconSize32)
        }

        let topStackView = UIStackView()

        addSubview(topStackView)
        topStackView.snp.makeConstraints { maker in
            maker.leading.equalTo(coinIconView.snp.trailing).offset(CGFloat.margin16)
            maker.top.equalToSuperview().inset(CGFloat.margin12)
            maker.trailing.equalToSuperview().inset(CGFloat.margin16)
        }

        topStackView.alignment = .center
        topStackView.distribution = .fill
        topStackView.axis = .horizontal
        topStackView.spacing = .margin8

        let bottomStackView = UIStackView()

        addSubview(bottomStackView)
        bottomStackView.snp.makeConstraints { maker in
            maker.leading.trailing.equalTo(topStackView)
            maker.top.equalTo(topStackView.snp.bottom).offset(1)
        }

        bottomStackView.alignment = .center
        bottomStackView.distribution = .fill
        bottomStackView.axis = .horizontal
        bottomStackView.spacing = .margin4

        topStackView.addArrangedSubview(nameLabel)
        nameLabel.font = .headline2
        nameLabel.textColor = .themeLeah
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        topStackView.addArrangedSubview(blockchainBadgeView)
        blockchainBadgeView.set(style: .small)

        let topSpacerView = UIView()
        topStackView.addArrangedSubview(topSpacerView)

        bottomStackView.addArrangedSubview(bottomLeftLabel)
        bottomLeftLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomLeftLabel.setContentHuggingPriority(.required, for: .horizontal)
        bottomLeftLabel.font = .headline2

        let bottomSpacerView = UIView()
        bottomStackView.addArrangedSubview(bottomSpacerView)

    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func bind(iconUrl: String, name: String, blockchainBadge: String, amount: String) {
        coinIconView.setImage(withUrlString: iconUrl, placeholder: nil)
        nameLabel.text = name
        blockchainBadgeView.text = blockchainBadge
        bottomLeftLabel.text = amount

    }

}
