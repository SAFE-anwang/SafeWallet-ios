import Foundation
import UIKit
import SnapKit
import ThemeKit
import ComponentKit
import BigInt

class LiquidityV3RecordDetailHeaderView: UITableViewHeaderFooterView {
    static let height: CGFloat = 250
    private let token0ImageView = UIImageView()
    private let token1ImageView = UIImageView()
    private let tokenNameLabel = UILabel()
    private let tokenIdLabel = UILabel()
    private let tickStateView = BadgeView()
    private let sliderTitleLabel = UILabel()
    private let sliderView = LiquiditySliderWrapper()
    
    var ratioOfRemove: ((Float) -> Void)?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .white
        sliderView.finishTracking = { [weak self] value in
            self?.ratioOfRemove?(value)
        }

        token0ImageView.contentMode = .scaleAspectFit
        contentView.addSubview(token0ImageView)
        token0ImageView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(CGFloat.margin16)
            make.size.equalTo(CGFloat.iconSize32)
        }
        
        token1ImageView.contentMode = .scaleAspectFit
        contentView.addSubview(token1ImageView)
        token1ImageView.snp.makeConstraints { make in
            make.leading.equalTo(token0ImageView.snp.trailing).offset(CGFloat.margin8)
            make.top.equalToSuperview().inset(CGFloat.margin16)
            make.size.equalTo(CGFloat.iconSize32)
        }
        
        tokenNameLabel.font = .headline2
        tokenNameLabel.textColor = .themeLeah
        contentView.addSubview(tokenNameLabel)
        tokenNameLabel.snp.makeConstraints { make in
            make.leading.equalTo(token1ImageView.snp.trailing).offset(CGFloat.margin8)
            make.trailing.equalToSuperview().inset(CGFloat.margin48)
            make.centerY.equalTo(token1ImageView)
            make.size.equalTo(CGFloat.iconSize32)
        }
        
        tokenIdLabel.font = .subhead2
        contentView.addSubview(tokenIdLabel)
        tokenIdLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.top.equalTo(token0ImageView.snp.bottom).offset(CGFloat.margin8)
        }
        
        tickStateView.set(style: .medium)
        contentView.addSubview(tickStateView)
        tickStateView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.centerY.equalTo(tokenNameLabel)
        }
        
        sliderTitleLabel.font = .caption
        sliderTitleLabel.text = "liquidity.remove.rate.title".localized
        contentView.addSubview(sliderTitleLabel)
        sliderTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(tokenIdLabel.snp.bottom).offset(CGFloat.margin24)
            make.leading.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        contentView.addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.top.equalTo(sliderTitleLabel.snp.bottom).offset(CGFloat.margin8)
            make.height.equalTo(LiquiditySliderWrapper.height)
        }
        
        
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func bind(viewItem: LiquidityV3RecordViewModel.V3RecordItem) {
        token1ImageView.setImage(withUrlString: viewItem.token0.coin.imageUrl, placeholder: nil)
        token0ImageView.setImage(withUrlString: viewItem.token1.coin.imageUrl, placeholder: nil)
        tokenNameLabel.text = viewItem.lpName
        tokenIdLabel.text = viewItem.tokenId
        tickStateView.text = viewItem.state
        tickStateView.backgroundColor = viewItem.color
    }
}
