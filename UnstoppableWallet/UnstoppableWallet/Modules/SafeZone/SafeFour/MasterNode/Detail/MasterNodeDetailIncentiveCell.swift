import UIKit
import ThemeKit
import SnapKit
import ComponentKit
import BigInt

class MasterNodeDetailIncentiveCell: BaseThemeCell {

    private let titleLabel = UILabel()
    private let creatorSliderView = MasterNodeSliderView()
    private let partnerSliderView = MasterNodeSliderView()
    override init(style: CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        set(backgroundStyle: .lawrence, isLast: true)
        
        titleLabel.text = "safe_zone.safe4.mining.reward".localized
        titleLabel.font = .subhead1
        wrapperView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
            make.height.equalTo(20)
            make.top.equalToSuperview().offset(CGFloat.margin12)
        }
        
        wrapperView.addSubview(creatorSliderView)
        creatorSliderView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.margin12)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
        
        wrapperView.addSubview(partnerSliderView)
        partnerSliderView.snp.makeConstraints { make in
            make.top.equalTo(creatorSliderView.snp.bottom).offset(CGFloat.margin12)
            make.leading.equalToSuperview().offset(CGFloat.margin16)
            make.trailing.equalToSuperview().inset(CGFloat.margin16)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func bind(creator: BigUInt, partner: BigUInt) {
        let creatorValue = Float(creator.description) ?? 0
        creatorSliderView.setTitle(text:  "safe_zone.safe4.node.creator".localized + "\(creatorValue)%")
        creatorSliderView.setSlider(value: creatorValue)
        
        let partnerValue = Float(partner.description) ?? 0
        partnerSliderView.setTitle(text: "safe_zone.safe4.partner".localized + "\(partnerValue)%")
        partnerSliderView.setSlider(value: partnerValue)
    }
    
    static func height() -> CGFloat {
        106
    }
}

class MasterNodeSliderView: UIView {
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
