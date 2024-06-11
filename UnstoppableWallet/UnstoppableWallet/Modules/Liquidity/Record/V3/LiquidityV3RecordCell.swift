import UIKit
import ThemeKit
import SnapKit
import ComponentKit

class LiquidityV3RecordCell: UITableViewCell {
    private static let margins = UIEdgeInsets(top: .margin4, left: .margin16, bottom: .margin4, right: .margin16)
    private let cardView = CardView(insets: .zero)
    private let token0ImageView = UIImageView()
    private let token1ImageView = UIImageView()
    private let tokenNameLabel = UILabel()
    private let tokenIdLabel = UILabel()
    private let feeView = BadgeView()
    private let tickStateView = BadgeView()
    private let tickRangeLabel = UILabel()
    
    private var viewItem: LiquidityV3RecordViewModel.V3RecordItem?
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
                
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview().inset(Self.margins)
        }
        
        token0ImageView.contentMode = .scaleAspectFit
        cardView.addSubview(token0ImageView)
        token0ImageView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(CGFloat.margin16)
            make.size.equalTo(CGFloat.iconSize32)
        }
        
        token1ImageView.contentMode = .scaleAspectFit
        cardView.addSubview(token1ImageView)
        token1ImageView.snp.makeConstraints { make in
            make.leading.equalTo(token0ImageView.snp.trailing).offset(CGFloat.margin4)
            make.top.equalToSuperview().inset(CGFloat.margin16)
            make.size.equalTo(CGFloat.iconSize32)
        }
        
        tokenNameLabel.font = .headline2
        tokenNameLabel.textColor = .themeLeah
        cardView.addSubview(tokenNameLabel)
        tokenNameLabel.snp.makeConstraints { make in
            make.leading.equalTo(token1ImageView.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.centerY.equalTo(token1ImageView)
            make.size.equalTo(CGFloat.iconSize32)
        }
        
        tokenIdLabel.font = .headline2
        cardView.addSubview(tokenIdLabel)
        tokenIdLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(CGFloat.margin16)
            make.centerY.equalToSuperview().offset(CGFloat.margin4)
        }
        
        feeView.set(style: .medium)
        feeView.backgroundColor = .clear
        feeView.textColor = .purple
        feeView.layer.borderColor = UIColor.purple.cgColor
        feeView.layer.borderWidth = 1
        cardView.addSubview(feeView)
        feeView.snp.makeConstraints { make in
            make.leading.equalTo(tokenIdLabel.snp.trailing).offset(CGFloat.margin8)
            make.centerY.equalToSuperview().offset(CGFloat.margin4)
        }
        
        tickStateView.set(style: .medium)
        cardView.addSubview(tickStateView)
        tickStateView.snp.makeConstraints { make in
            make.leading.equalTo(feeView.snp.trailing).offset(CGFloat.margin8)
            make.centerY.equalToSuperview().offset(CGFloat.margin4)
        }
        
        tickRangeLabel.font = .subhead2
        cardView.addSubview(tickRangeLabel)
        tickRangeLabel.snp.makeConstraints { make in
            make.bottom.leading.equalToSuperview().inset(CGFloat.margin16)
        }

    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    func bind(viewItem: LiquidityV3RecordViewModel.V3RecordItem) {
        
        self.viewItem = viewItem
        
        token1ImageView.setImage(withUrlString: viewItem.token0.coin.imageUrl, placeholder: nil)
        token0ImageView.setImage(withUrlString: viewItem.token1.coin.imageUrl, placeholder: nil)
        tokenNameLabel.text = viewItem.lpName
        tokenIdLabel.text = viewItem.tokenId
        feeView.text = viewItem.fee
        
        tickStateView.text = viewItem.state
        tickStateView.backgroundColor = viewItem.color
        
        tickRangeLabel.text = viewItem.tickRangeDesc
    }
    
    static func height() -> CGFloat {
        return 130
    }
}
