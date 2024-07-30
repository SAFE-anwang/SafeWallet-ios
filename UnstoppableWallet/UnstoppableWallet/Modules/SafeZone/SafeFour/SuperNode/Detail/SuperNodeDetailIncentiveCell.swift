import UIKit
import ThemeKit
import SnapKit
import ComponentKit
import BigInt

class SuperNodeDetailIncentiveCell: UITableViewCell {
    private let margins = UIEdgeInsets(top: 1, left: .margin16, bottom: 0, right: .margin16)
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let creatorSliderView = SuperNodeSliderView()
    private let partnerSliderView = SuperNodeSliderView()
    private let voterSliderView = SuperNodeSliderView()
    
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        cardView.backgroundColor = .white
        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(margins)
        }
        
        titleLabel.text = "挖矿奖励分配:".localized
        titleLabel.font = .subhead1
        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(20)
            make.top.equalToSuperview().offset(CGFloat.margin12)
        }
        
        cardView.addSubview(creatorSliderView)
        creatorSliderView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin12)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        cardView.addSubview(partnerSliderView)
        partnerSliderView.snp.makeConstraints { make in
            make.top.equalTo(creatorSliderView.snp.bottom).offset(CGFloat.margin12)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        cardView.addSubview(voterSliderView)
        voterSliderView.snp.makeConstraints { make in
            make.top.equalTo(partnerSliderView.snp.bottom).offset(CGFloat.margin12)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(creator: BigUInt, partner: BigUInt, voter: BigUInt) {
        let creatorValue = Float(creator.description) ?? 0
        creatorSliderView.setTitle(text: "创建者\(creatorValue)%")
        creatorSliderView.setSlider(value: creatorValue)
        
        let partnerValue = Float(partner.description) ?? 0
        partnerSliderView.setTitle(text: "合伙人\(partnerValue)%")
        partnerSliderView.setSlider(value: partnerValue)
        
        let voterValue = Float(voter.description) ?? 0
        voterSliderView.setTitle(text: "投票人\(voterValue)%")
        voterSliderView.setSlider(value: voterValue)
    }
    
    static func height() -> CGFloat {
        136
    }
}

class SuperNodeSliderView: UIView {
    private let titleLabel = UILabel()
    private let slider = UISlider()
    
    init() {
        super.init(frame: .zero)
        
        titleLabel.font = .subhead1
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.leading.equalToSuperview()
        }
        
        slider.setThumbImage(UIImage(), for: .normal)
        slider.isUserInteractionEnabled = false
        slider.minimumValue = 0
        slider.maximumValue = 100
        addSubview(slider)
        slider.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.leading.equalTo(titleLabel.snp.trailing).offset(CGFloat.margin8)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setTitle(text: String) {
        titleLabel.text = text
    }
    
    func setSlider(value: Float) {
        slider.value = value
    }
}

